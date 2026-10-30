import { Project, ProjectSummary, store } from '../vera/ProjectStore'
import { projectOperations, ProjectOperationStatus } from '../vera/ProjectOperations'
import { refreshForms } from '../vera/FormUpdater'
import { common } from '@kit.AbilityKit'
import { app } from './AppStyle'

export class ProjectNavParams {
  projectId: string = ''
}

/** A project and what its row shows of it. */
export class ProjectRow {
  project: Project = new Project()
  summary: ProjectSummary = new ProjectSummary()
}

/** Newest work first: by when a project's latest version was saved, or when it was made if it has none. */
export function loadProjectRows(): ProjectRow[] {
  let rows: ProjectRow[] = []
  for (let project of store.listProjects()) {
    let row = new ProjectRow()
    row.project = project
    row.summary = store.summaryOf(project)
    rows.push(row)
  }
  rows.sort((a: ProjectRow, b: ProjectRow): number => b.summary.updatedAt - a.summary.updatedAt)
  return rows
}

/** The rows, handed to a LazyForEach so only the ones on screen build their picture. */
export class RowSource implements IDataSource {
  rows: ProjectRow[] = []
  private listeners: DataChangeListener[] = []

  totalCount(): number { return this.rows.length }
  getData(index: number): ProjectRow { return this.rows[index] }
  registerDataChangeListener(listener: DataChangeListener): void {
    if (this.listeners.indexOf(listener) < 0) { this.listeners.push(listener) }
  }
  unregisterDataChangeListener(listener: DataChangeListener): void {
    const at = this.listeners.indexOf(listener)
    if (at >= 0) { this.listeners.splice(at, 1) }
  }
  replace(rows: ProjectRow[]): void {
    this.rows = rows
    for (const l of this.listeners) { l.onDataReloaded() }
  }
}

/** Asks, then deletes the project with its shortcut and forms; `done` runs after either way. */
export function confirmDeleteProject(ui: UIContext, id: string, done: () => void): void {
  let project = store.getProject(id)
  if (project === null) { return }
  ui.showAlertDialog({
    title: 'Delete mini-app?',
    message: 'Delete "' + project.name + '" and all its saved versions and data? This cannot be undone.',
    primaryButton: {
      value: 'Cancel',
      action: () => {}
    },
    secondaryButton: {
      value: 'Delete',
      fontColor: app.danger,
      action: () => { deleteProject(ui, id, done) }
    }
  })
}

async function deleteProject(ui: UIContext, id: string, done: () => void): Promise<void> {
  let context = (): common.UIAbilityContext => ui.getHostContext() as common.UIAbilityContext
  const status = await projectOperations.deleteProject(context, id)
  done()
  refreshForms()
  if (status !== ProjectOperationStatus.Success) {
    const message = status === ProjectOperationStatus.ProjectDeletedShortcutRemovalFailed ?
      'Mini-application was deleted, but its shortcut cannot be removed.' : 'Error deleting mini-app.'
    try {
      ui.getPromptAction().showToast({ message: message })
    } catch (toastError) {
      console.error('Show deletion error failed: ' + (toastError as Error).message)
    }
  }
}

/** Tile colours for the home strip; a project keeps the one its id picks. */
const TILE_TINTS: string[] = ['#331F9D6B', '#33E0892B', '#335B4CF0', '#330E8FA8', '#33E5533D', '#33D6336C', '#33A0700F', '#333B4A5C']

export function tileTint(id: string): string {
  let h = 0
  for (let i = 0; i < id.length; i++) { h = (h * 31 + id.charCodeAt(i)) % 997 }
  return TILE_TINTS[h % TILE_TINTS.length]
}
