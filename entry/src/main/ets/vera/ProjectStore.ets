import fs from '@ohos.file.fs'

export class Project {
  id: string = ''
  name: string = ''
  icon: string = ''
  createdAt: number = 0
}

export class Version {
  id: string = ''
  projectId: string = ''
  source: string = ''
  vbc2: string = ''
  note: string = ''
  createdAt: number = 0
}

function generateId(): string {
  let now = Date.now()
  let rand = Math.floor(Math.random() * 0xFFFFFF)
  return now.toString(36) + rand.toString(36)
}

function ensureDir(path: string): void {
  try { fs.mkdirSync(path, true) } catch (_e) {}
}

function readJson(path: string): string {
  try {
    let stat = fs.statSync(path)
    if (stat.size === 0) { return '' }
    return fs.readTextSync(path)
  } catch (_e) {
    return ''
  }
}

function writeJson(path: string, content: string): void {
  let file = fs.openSync(path, fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC)
  fs.writeSync(file.fd, content)
  fs.closeSync(file)
}

function removeRecursive(path: string): void {
  try { fs.rmdirSync(path) } catch (_e) {}
}

export class ProjectStore {
  private root: string = ''

  init(filesDir: string): void {
    this.root = filesDir + '/vera'
    ensureDir(this.root)
  }

  private indexPath(): string { return this.root + '/index.json' }
  private projectDir(id: string): string { return this.root + '/' + id }
  private versionPath(projectId: string, versionId: string): string {
    return this.projectDir(projectId) + '/' + versionId + '.json'
  }

  private readIndex(): Project[] {
    let text = readJson(this.indexPath())
    if (text.length === 0) { return [] }
    try {
      let arr = JSON.parse(text) as Object[]
      let result: Project[] = []
      for (let item of arr) {
        let p = new Project()
        let obj = item as Record<string, Object>
        p.id = obj['id'] as string
        p.name = obj['name'] as string
        p.icon = obj['icon'] as string
        p.createdAt = obj['createdAt'] as number
        result.push(p)
      }
      return result
    } catch (_e) { return [] }
  }

  private writeIndex(projects: Project[]): void {
    let arr: Object[] = []
    for (let p of projects) {
      let obj: Record<string, Object> = {}
      obj['id'] = p.id
      obj['name'] = p.name
      obj['icon'] = p.icon
      obj['createdAt'] = p.createdAt
      arr.push(obj)
    }
    writeJson(this.indexPath(), JSON.stringify(arr))
  }

  listProjects(): Project[] {
    return this.readIndex()
  }

  getProject(id: string): Project | null {
    let projects = this.readIndex()
    for (let p of projects) {
      if (p.id === id) { return p }
    }
    return null
  }

  createProject(name: string, icon: string): Project {
    let p = new Project()
    p.id = generateId()
    p.name = name
    p.icon = icon
    p.createdAt = Date.now()
    let projects = this.readIndex()
    projects.push(p)
    this.writeIndex(projects)
    ensureDir(this.projectDir(p.id))
    return p
  }

  updateProject(id: string, name: string, icon: string): void {
    let projects = this.readIndex()
    for (let p of projects) {
      if (p.id === id) {
        p.name = name
        p.icon = icon
        break
      }
    }
    this.writeIndex(projects)
  }

  deleteProject(id: string): void {
    let projects = this.readIndex()
    let filtered: Project[] = []
    for (let p of projects) {
      if (p.id !== id) { filtered.push(p) }
    }
    this.writeIndex(filtered)
    removeRecursive(this.projectDir(id))
  }

  listVersions(projectId: string): Version[] {
    let dir = this.projectDir(projectId)
    let versions: Version[] = []
    try {
      let files = fs.listFileSync(dir)
      for (let file of files) {
        if (!file.endsWith('.json')) { continue }
        let text = readJson(dir + '/' + file)
        if (text.length === 0) { continue }
        let v = this.parseVersion(text)
        if (v !== null) { versions.push(v!) }
      }
    } catch (_e) {}
    versions.sort((a: Version, b: Version): number => b.createdAt - a.createdAt)
    return versions
  }

  getVersion(projectId: string, versionId: string): Version | null {
    let text = readJson(this.versionPath(projectId, versionId))
    if (text.length === 0) { return null }
    return this.parseVersion(text)
  }

  getLatestVersion(projectId: string): Version | null {
    let versions = this.listVersions(projectId)
    if (versions.length === 0) { return null }
    return versions[0]
  }

  createVersion(projectId: string, source: string, vbc2: string, note: string): Version {
    ensureDir(this.projectDir(projectId))
    let v = new Version()
    v.id = generateId()
    v.projectId = projectId
    v.source = source
    v.vbc2 = vbc2
    v.note = note
    v.createdAt = Date.now()
    let obj: Record<string, Object> = {}
    obj['id'] = v.id
    obj['projectId'] = v.projectId
    obj['source'] = v.source
    obj['vbc2'] = v.vbc2
    obj['note'] = v.note
    obj['createdAt'] = v.createdAt
    writeJson(this.versionPath(projectId, v.id), JSON.stringify(obj))
    return v
  }

  updateVersionVbc2(projectId: string, versionId: string, vbc2: string): void {
    let v = this.getVersion(projectId, versionId)
    if (v === null) { return }
    v!.vbc2 = vbc2
    let obj: Record<string, Object> = {}
    obj['id'] = v!.id
    obj['projectId'] = v!.projectId
    obj['source'] = v!.source
    obj['vbc2'] = v!.vbc2
    obj['note'] = v!.note
    obj['createdAt'] = v!.createdAt
    writeJson(this.versionPath(projectId, versionId), JSON.stringify(obj))
  }

  deleteVersion(projectId: string, versionId: string): void {
    try { fs.unlinkSync(this.versionPath(projectId, versionId)) } catch (_e) {}
  }

  private parseVersion(text: string): Version | null {
    try {
      let obj = JSON.parse(text) as Record<string, Object>
      let v = new Version()
      v.id = obj['id'] as string
      v.projectId = obj['projectId'] as string
      v.source = obj['source'] as string
      v.vbc2 = (obj['vbc2'] as string) || ''
      v.note = (obj['note'] as string) || ''
      v.createdAt = obj['createdAt'] as number
      return v
    } catch (_e) { return null }
  }
}

export const store: ProjectStore = new ProjectStore()
