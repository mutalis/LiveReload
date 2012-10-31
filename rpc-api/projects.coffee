debug = require('debug')('livereload:cli')
Path  = require 'path'
fs    = require 'fs'
_     = require 'underscore'

_session = null
_vfs = null
_dataFile = null
_selectedProject = null

_stats = {
  connectionCount: 0
  changes:       0
  compilations:  0
  refreshes:     0
}
_status = ""

n = (number, strings...) ->
  variant = (if number is 1 then 0 else 1)
  string = strings[variant]
  return string.replace('#', number)


sendStatus = ->
  message = _status or "Idle. #{n _stats.connectionCount, '1 browser connected', '# browsers connected'}. #{n _stats.changes, '1 change', '# changes'}, #{n _stats.compilations, '1 file compiled', '# files compiled'}, #{n _stats.refreshes, '1 refresh', '# refreshes'} so far."
  # LR.rpc.send 'status', { status: message }
  UPDATE '#mainwnd': '#textBlockStatus': 'text': message

sendStatus = _.throttle(sendStatus, 50)


sendProjectPaneUpdate = ->
  data = []
  if _selectedProject
    for dummy, file of _selectedProject.fileOptionsByPath when file.compiler
      data.push { id: file.relpath, text: "#{file.relpath}   →   #{file.destRelPath}" }

  UPDATE
    '#mainwnd':
      '#treeViewPaths':
        'data': data
      '#buttonSetOutputFolder': {}


sendUpdate = ->
  LR.rpc.send 'update', {
    projects:
      for project in _session.projects
        {
          id:       project.id
          name:     project.name
          path:     project.path
          url:      project.urls.join(", ")
          snippet:  project.snippet
          compilationEnabled: !!project.compilationEnabled
        }
  }
  sendProjectPaneUpdate()
  sendStatus()


saveProjects = ->
  _session.makeProjectsMemento (err, projects) ->
    throw err if err
    memento = { projects }
    fs.writeFileSync(_dataFile, JSON.stringify(memento, null, 2))
    sendUpdate()


setStatus = (status) ->
  _status = status
  sendStatus()


UPDATE = (payload, callback) ->
  LR.rpc.send 'rpc', payload, callback


UI =
  '#mainwnd':
    '#buttonSetOutputFolder':
      'click': (arg) ->
        setStatus "HELLO #{Date.now()}"
        UPDATE '#mainwnd': '#buttonSetOutputFolder': label: "HELLO #{Date.now()} ;-)"

        initial = _selectedProject?.fullPath ? null

        UPDATE { '#mainwnd': '!chooseOutputFolder': [{ initial: initial }] }, (err, result) ->
          setStatus "Result = #{JSON.stringify(result)}"

  update: (payload) ->
    @_updateWithContext(payload, this)

  _updateWithContext: (payload, context) ->
    if typeof context is 'function'
      context(payload)
    else
      for own key, value of payload
        if subcontext = context[key]
          @_updateWithContext(value, subcontext)


exports.init = (vfs, session, appDataDir) ->
  _vfs = vfs
  _session = session
  _dataFile = Path.join(appDataDir, 'projects.json')

  session.on 'run.start', (project, run) =>
    _stats.changes += run.change.paths.length

  session.on 'run.finish', (project, run) =>
    LR.client.projects.notifyChanged({})
    setStatus ''
    saveProjects()


  statusClearingTimeout = null

  session.on 'action.start', (project, action) =>
    switch action.id
      when 'compile'
        _stats.compilations += 1
      when 'refresh'
        _stats.refreshes += 1

    clearTimeout(statusClearingTimeout) if statusClearingTimeout?
    setStatus action.message + "..."

  session.on 'action.finish', (project, action) =>
    clearTimeout(statusClearingTimeout) if statusClearingTimeout?
    statusClearingTimeout = setTimeout((-> setStatus ''), 50)


  if fs.existsSync(_dataFile)
    try
      data = JSON.parse(fs.readFileSync(_dataFile, 'utf8'))
    catch e
      data = null
    if data
      _session.setProjectsMemento _vfs, (data.projects or [])

  sendUpdate()


exports.api =
  add: ({ path }, callback) ->
    _session.addProject _vfs, path
    saveProjects()
    callback()

  remove: ({ id }, callback) ->
    if project = _session.findProjectById(id)
      project.destroy()
    saveProjects()
    callback()

  update: ({ id, compilationEnabled, url }, callback) ->
    if project = _session.findProjectById(id)
      if compilationEnabled?
        project.compilationEnabled = !!compilationEnabled
      if url?
        project.urls = url.split(/[\s,]+/).filter((u) -> u.length > 0)
    saveProjects()
    callback()

  changeDetected: ({ id, changes }, callback) ->

  setSelectedProject: ({ id }, callback) ->
    _selectedProject = _session.findProjectById(id)
    sendProjectPaneUpdate()

  rpc: (payload, callback) ->
    UI.update(payload)
    callback()


exports.setConnectionStatus = ({ connectionCount }) ->
  _stats.connectionCount = connectionCount
  sendStatus()
