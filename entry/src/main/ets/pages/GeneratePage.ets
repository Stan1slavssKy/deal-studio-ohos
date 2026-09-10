import router from '@ohos.router'
import fs from '@ohos.file.fs'
import http from '@ohos.net.http'
import request from '@ohos.request'
import { store } from '../vera/ProjectStore'
import { refreshForms } from '../vera/FormUpdater'
import { engine, LlamaEngine, GenerateRequest, GenerateResult, loadRawfileText } from '../vera/LlamaEngine'
import { compileVeraSource, CompileError } from '../vera/VeraCompiler'
import { deepseek } from '../vera/DeepSeekEngine'
import { settings } from '../vera/SettingsStore'

const MAX_RETRIES: number = 3
const DEFAULT_SERVER_URL: string = 'http://31.77.129.17:8787'

// DeepSeek and Local both run the agent loop on the device and differ only in
// which model writes the code; Server hands the whole job to vera-server.
const MODE_DEEPSEEK: string = 'deepseek'
const MODE_SERVER: string = 'server'
const MODE_LOCAL: string = 'local'

class ServerDecodedResponse {
  source: string = ''
  bytecode: string = ''
}

class RefineRequest {
  prompt: string = ''
  previousSource: string = ''
}

class AttemptMetrics {
  attempt: number = 0
  genMs: number = 0
  compileMs: number = 0
  inputTokens: number = 0
  outputTokens: number = 0
  cacheHitTokens: number = 0
  success: boolean = false
}

function decodeServerResponse(body: string): ServerDecodedResponse {
  let lines = body.split('\n')
  let sourceLines: string[] = []
  let bytecodeLines: string[] = []
  let inSource = false
  let foundSource = false
  for (let line of lines) {
    if (line === ';vera-source-begin') {
      inSource = true
      foundSource = true
      continue
    }
    if (line === ';vera-source-end' && inSource) {
      inSource = false
      continue
    }
    if (inSource) {
      if (line.startsWith(';|')) {
        sourceLines.push(line.substring(2))
      }
      continue
    }
    bytecodeLines.push(line)
  }
  let result = new ServerDecodedResponse()
  result.source = foundSource ? sourceLines.join('\n') : ''
  result.bytecode = bytecodeLines.join('\n')
  return result
}

@Entry
@Component
struct GeneratePage {
  @State projectId: string = ''
  @State baseVersionId: string = ''
  @State prompt: string = ''
  @State generatedSource: string = ''
  @State status: string = ''
  @State generating: boolean = false
  @State modelReady: boolean = false
  @State mode: string = MODE_DEEPSEEK
  @State attempt: number = 0
  @State compiled: boolean = false
  @State compileErrors: string = ''
  @State showCode: boolean = false
  @State showMetrics: boolean = false
  @State attempts: AttemptMetrics[] = []
  @State totalMs: number = 0
  private systemPrompt: string = ''
  private grammar: string = ''
  private previousSource: string = ''
  private genStartTime: number = 0
  private cancelRequested: boolean = false
  private serverBytecode: string = ''

  aboutToAppear(): void {
    let params = router.getParams() as Record<string, string>
    if (params !== null && params !== undefined) {
      this.projectId = params['projectId'] || ''
      this.baseVersionId = params['baseVersionId'] || ''
    }
    if (this.baseVersionId.length > 0) {
      let v = store.getVersion(this.projectId, this.baseVersionId)
      if (v !== null) { this.previousSource = v!.source }
    }
    settings.init(getContext(this).filesDir)
    this.loadResources()
  }

  // The key can arrive from a launch parameter while this page sits in the
  // foreground, so re-read it whenever the page comes back into view.
  onPageShow(): void {
    if (this.mode === MODE_DEEPSEEK && !this.generating) {
      this.checkDeepSeek()
    }
  }

  private async loadResources(): Promise<void> {
    try {
      let mgr = getContext(this).resourceManager
      this.systemPrompt = await loadRawfileText(mgr, 'vera-skill.txt')
      this.grammar = await loadRawfileText(mgr, 'vera.gbnf')
      this.status = 'Resources loaded'
    } catch (e) {
      this.status = 'Failed to load resources: ' + (e as Error).message
    }
    this.checkProvider()
  }

  private checkProvider(): void {
    if (this.mode === MODE_DEEPSEEK) {
      this.checkDeepSeek()
    } else if (this.mode === MODE_SERVER) {
      this.checkServer()
    } else {
      this.checkModel()
    }
  }

  private checkDeepSeek(): void {
    if (settings.hasApiKey()) {
      this.status = 'DeepSeek ready (' + settings.getModel() + ', key ' + settings.maskedKey() + ')'
    } else {
      this.status = 'No API key. Send one with: aa start -a EntryAbility -b com.vera.probe.dyn --ps deepseekKey <key>'
    }
  }

  private async checkServer(): Promise<void> {
    this.status = 'Checking server...'
    let client = http.createHttp()
    try {
      let resp = await client.request(DEFAULT_SERVER_URL + '/health', {
        method: http.RequestMethod.GET,
        connectTimeout: 5000,
        readTimeout: 5000
      })
      if (resp.responseCode === 200) {
        let body = resp.result as string
        let health = JSON.parse(body) as Record<string, Object>
        this.status = 'Server ready (' + (health['model'] as string) + ')'
      } else {
        this.status = 'Server error: HTTP ' + resp.responseCode
      }
    } catch (e) {
      this.status = 'Server unreachable: ' + (e as Error).message
    } finally {
      client.destroy()
    }
  }

  private async checkModel(): Promise<void> {
    let filesDir = getContext(this).filesDir
    let modelPath = LlamaEngine.defaultModelPath(filesDir)
    if (!LlamaEngine.modelExists(filesDir)) {
      // hdc file send is blocked on release-provisioned installs, so the
      // model is fetched from the vera-server /models endpoint instead.
      await this.downloadModel(modelPath)
    }
    this.modelReady = LlamaEngine.modelExists(filesDir)
    if (!this.modelReady) {
      this.status = 'Model not found'
      return
    }
    this.status = 'Model ready'
    if (!engine.isReady()) {
      this.status = 'Loading model...'
      let ok = engine.init({
        modelPath: modelPath,
        nCtx: 4096,
        nThreads: 4,
        nGpuLayers: 0
      })
      this.status = ok ? 'Model loaded' : 'Model load failed'
      this.modelReady = ok
    }
  }

  private async downloadModel(modelPath: string): Promise<void> {
    let filesDir = getContext(this).filesDir
    try {
      fs.mkdirSync(filesDir + '/models', true)
    } catch (_e) {}
    this.status = 'Downloading model (one-time, ~1.9GB)...'
    try {
      let task = await request.downloadFile(getContext(this), {
        url: DEFAULT_SERVER_URL + '/models/qwen2.5-coder-3b-instruct-q4_k_m.gguf',
        filePath: modelPath
      })
      task.on('progress', (received: number, total: number): void => {
        if (total > 0) {
          this.status = 'Downloading model ' + Math.floor(received * 100 / total).toString() + '%'
        }
      })
      await new Promise<void>((resolve, reject) => {
        task.on('complete', (): void => { resolve() })
        task.on('fail', (err: number): void => { reject(new Error('download failed, code ' + err.toString())) })
      })
      this.status = 'Model downloaded'
    } catch (e) {
      this.status = 'Model download failed: ' + (e as Error).message
    }
  }

  private doGenerate(): void {
    if (this.prompt.trim().length === 0) { return }
    if (this.mode === MODE_SERVER) {
      this.doServerGenerate()
      return
    }
    if (this.mode === MODE_DEEPSEEK && !settings.hasApiKey()) {
      this.checkDeepSeek()
      return
    }
    if (this.mode === MODE_LOCAL && !this.modelReady) { return }
    this.generating = true
    this.generatedSource = ''
    this.compiled = false
    this.compileErrors = ''
    this.attempt = 1
    this.attempts = []
    this.totalMs = 0
    this.serverBytecode = ''
    this.cancelRequested = false
    this.genStartTime = Date.now()
    this.status = 'Generating (attempt 1/' + MAX_RETRIES + ')...'
    this.runAttempt(this.prompt.trim(), '')
  }

  private async doServerGenerate(): Promise<void> {
    this.generating = true
    this.generatedSource = ''
    this.compiled = false
    this.compileErrors = ''
    this.attempts = []
    this.totalMs = 0
    this.serverBytecode = ''
    this.genStartTime = Date.now()
    this.status = this.previousSource.length > 0 ? 'Server refining...' : 'Server generating...'

    let metrics = new AttemptMetrics()
    metrics.attempt = 1
    let client = http.createHttp()
    try {
      let genStart = Date.now()
      // Refinement: send the base version's source so the server can edit it
      // instead of regenerating from scratch.
      let requestBody: string = this.prompt.trim()
      let contentType: string = 'text/plain; charset=utf-8'
      if (this.previousSource.length > 0) {
        let refine = new RefineRequest()
        refine.prompt = this.prompt.trim()
        refine.previousSource = this.previousSource
        requestBody = JSON.stringify(refine)
        contentType = 'application/json'
      }
      let resp = await client.request(DEFAULT_SERVER_URL + '/compile', {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': contentType },
        extraData: requestBody,
        connectTimeout: 10000,
        readTimeout: 180000
      })
      metrics.genMs = Date.now() - genStart

      if (resp.responseCode === 200) {
        let body = resp.result as string
        let decoded = decodeServerResponse(body)
        this.generatedSource = decoded.source
        this.serverBytecode = decoded.bytecode
        this.compiled = true
        this.compileErrors = ''
        metrics.success = true
        this.status = 'Server compiled successfully'
      } else {
        let body = resp.result as string
        try {
          let errObj = JSON.parse(body) as Record<string, Object>
          let diags = errObj['diagnostics'] as Object[]
          if (diags !== null && diags !== undefined && diags.length > 0) {
            let firstDiag = diags[0] as Record<string, Object>
            let msg = (firstDiag['message'] as string) || ''
            let generatedSrc = (firstDiag['generatedSource'] as string) || ''
            if (generatedSrc.length > 0) {
              this.generatedSource = generatedSrc
            }
            this.compileErrors = msg
          } else {
            this.compileErrors = 'Server error: HTTP ' + resp.responseCode
          }
        } catch (_e) {
          this.compileErrors = 'Server error: HTTP ' + resp.responseCode + ' — ' + body.substring(0, 200)
        }
        this.status = 'Server generation failed'
      }
    } catch (e) {
      this.compileErrors = 'Request failed: ' + (e as Error).message
      this.status = 'Server unreachable'
    } finally {
      client.destroy()
    }

    this.attempts = [metrics]
    this.totalMs = Date.now() - this.genStartTime
    this.generating = false
  }

  /**
   * The one place that knows which model is behind the loop. Everything after
   * it -- compile, collect diagnostics, retry -- is identical for both.
   */
  private callModel(request: GenerateRequest, onToken: (token: string) => void): Promise<GenerateResult> {
    if (this.mode === MODE_DEEPSEEK) {
      // deepseek-flash thinks by default, and the reasoning comes out of the
      // same token budget as the program: an 8K cap was being spent thinking
      // and the program arrived truncated. A first attempt does not need it --
      // the output format is fixed and the programs are short. A retry has
      // compiler diagnostics to work through, so it gets both.
      let retry = this.attempt > 1
      deepseek.setThinking(retry)
      request.maxTokens = retry ? 32768 : 8192
      return deepseek.generate(request, onToken)
    }
    return Promise.resolve(engine.generate(request, onToken))
  }

  private async runAttempt(userPrompt: string, errorFeedback: string): Promise<void> {
    this.generatedSource = ''
    let metrics = new AttemptMetrics()
    metrics.attempt = this.attempt

    let request = new GenerateRequest()
    request.systemPrompt = this.systemPrompt
    request.grammar = this.grammar
    request.maxTokens = 2048
    request.temperature = 0.2

    if (errorFeedback.length > 0) {
      request.previousSource = this.previousSource.length > 0 ? this.previousSource : ''
      request.userPrompt = userPrompt + '\n\nThe previous attempt had compile errors:\n' + errorFeedback + '\n\nFix these errors and generate the complete program.'
    } else if (this.previousSource.length > 0) {
      request.previousSource = this.previousSource
      request.userPrompt = userPrompt
    } else {
      request.userPrompt = userPrompt
    }

    let genStart = Date.now()
    let genResult: GenerateResult
    try {
      genResult = await this.callModel(request, (token: string) => {
        this.generatedSource += token
      })
      if (genResult.text.length > 0) {
        this.generatedSource = genResult.text
      }
    } catch (e) {
      this.status = 'Generation failed: ' + (e as Error).message
      this.generating = false
      return
    }
    metrics.genMs = Date.now() - genStart
    if (this.cancelRequested) {
      this.attempts = [...this.attempts, metrics]
      this.totalMs = Date.now() - this.genStartTime
      this.status = 'Stopped'
      this.generating = false
      return
    }
    metrics.inputTokens = genResult.inputTokens
    metrics.outputTokens = genResult.outputTokens
    if (this.mode === MODE_DEEPSEEK) {
      metrics.cacheHitTokens = deepseek.lastCacheHitTokens()
    }

    if (this.generatedSource.trim().length === 0) {
      this.status = 'Generation produced empty output'
      this.generating = false
      this.attempts = [...this.attempts, metrics]
      this.totalMs = Date.now() - this.genStartTime
      return
    }

    this.status = 'Compiling (attempt ' + this.attempt + '/' + MAX_RETRIES + ')...'
    let vbc2 = ''
    let errors = ''
    let compileStart = Date.now()
    try {
      let result = compileVeraSource(this.generatedSource.trim())
      vbc2 = result.vbc2
    } catch (e) {
      if (e instanceof CompileError) {
        errors = e.message
      } else {
        errors = (e as Error).message
      }
    }
    metrics.compileMs = Date.now() - compileStart

    // A program cut off at the token ceiling fails to parse somewhere near its
    // end. Saying so is worth more to the next attempt than the parse error,
    // which describes the cut rather than the mistake.
    if (errors.length > 0 && this.mode === MODE_DEEPSEEK && deepseek.lastFinishReason() === 'length') {
      errors = 'The previous attempt was cut off at the output token limit before the program ended, so it did not parse. Write a shorter program.\n' + errors
    }

    if (errors.length === 0 && vbc2.length > 0) {
      metrics.success = true
      this.attempts = [...this.attempts, metrics]
      this.totalMs = Date.now() - this.genStartTime
      this.compiled = true
      this.compileErrors = ''
      this.status = 'Compiled successfully on attempt ' + this.attempt
      this.generating = false
      return
    }

    this.attempts = [...this.attempts, metrics]
    this.compileErrors = errors
    if (this.attempt < MAX_RETRIES) {
      this.attempt++
      this.status = 'Compile failed, retrying (attempt ' + this.attempt + '/' + MAX_RETRIES + ')...'
      await this.runAttempt(userPrompt, errors)
    } else {
      this.totalMs = Date.now() - this.genStartTime
      this.status = 'Compilation failed after ' + MAX_RETRIES + ' attempts'
      this.generating = false
    }
  }

  private doSave(): void {
    if (this.generatedSource.trim().length === 0) { return }
    let note = this.prompt.trim()
    if (note.length > 100) { note = note.substring(0, 100) + '...' }
    let vbc2 = ''
    if (this.compiled && this.serverBytecode.length > 0) {
      vbc2 = this.serverBytecode
    } else if (this.compiled) {
      try {
        let result = compileVeraSource(this.generatedSource.trim())
        vbc2 = result.vbc2
      } catch (_e) {}
    }
    store.createVersion(this.projectId, this.generatedSource.trim(), vbc2, note)
    this.status = vbc2.length > 0 ? 'Saved with compiled bytecode' : 'Saved (source only — compile errors)'
    refreshForms()
    router.back()
  }

  private formatMs(ms: number): string {
    if (ms < 1000) return ms + 'ms'
    let secs = (ms / 1000).toFixed(1)
    return secs + 's'
  }

  private modeLabel(): string {
    if (this.mode === MODE_DEEPSEEK) { return 'DeepSeek' }
    if (this.mode === MODE_SERVER) { return 'Server' }
    return 'Local'
  }

  private modeSubtitle(): string {
    if (this.mode === MODE_DEEPSEEK) { return settings.getModel() + ' - agent loop on device' }
    if (this.mode === MODE_SERVER) { return DEFAULT_SERVER_URL }
    return 'On-device Qwen3-Coder-3B'
  }

  private modeTint(): string {
    if (this.mode === MODE_DEEPSEEK) { return '#E8F5E9' }
    if (this.mode === MODE_SERVER) { return '#E3F2FD' }
    return '#FFF3E0'
  }

  private modeInk(): string {
    if (this.mode === MODE_DEEPSEEK) { return '#2E7D32' }
    if (this.mode === MODE_SERVER) { return '#1565C0' }
    return '#E65100'
  }

  private nextMode(): string {
    if (this.mode === MODE_DEEPSEEK) { return MODE_SERVER }
    if (this.mode === MODE_SERVER) { return MODE_LOCAL }
    return MODE_DEEPSEEK
  }

  private canGenerate(): boolean {
    if (this.mode === MODE_SERVER) { return true }
    if (this.mode === MODE_DEEPSEEK) { return settings.hasApiKey() }
    return this.modelReady
  }

  private totalCacheHitTokens(): number {
    let total = 0
    for (let a of this.attempts) total += a.cacheHitTokens
    return total
  }

  private totalInputTokens(): number {
    let total = 0
    for (let a of this.attempts) total += a.inputTokens
    return total
  }

  private totalOutputTokens(): number {
    let total = 0
    for (let a of this.attempts) total += a.outputTokens
    return total
  }

  build() {
    Navigation() {
      Column() {
        if (this.previousSource.length > 0) {
          Text('Refining existing version')
            .fontSize(13).fontColor('#007DFF').padding({ left: 16, top: 8 })
        }

        Row({ space: 8 }) {
          Button(this.modeLabel())
            .type(ButtonType.Normal)
            .fontSize(12)
            .height(30)
            .backgroundColor(this.modeTint())
            .fontColor(this.modeInk())
            .enabled(!this.generating)
            .onClick(() => {
              this.mode = this.nextMode()
              this.checkProvider()
            })
          Text(this.modeSubtitle())
            .fontSize(11).fontColor('#999999').layoutWeight(1)
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8 })

        TextArea({ placeholder: 'Describe the app you want...', text: this.prompt })
          .onChange((value: string) => { this.prompt = value })
          .width('100%')
          .height(100)
          .margin(16)

        Row({ space: 10 }) {
          Button(this.generating ? 'Stop' : 'Generate')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .enabled(this.canGenerate() || this.generating)
            .onClick(() => {
              if (this.generating) {
                this.cancelRequested = true
                if (this.mode === MODE_LOCAL) { engine.stop() }
                if (this.mode === MODE_DEEPSEEK) { deepseek.stop() }
                this.generating = false
                this.totalMs = Date.now() - this.genStartTime
                this.status = 'Stopped'
              } else {
                this.doGenerate()
              }
            })
          Button('Save')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .enabled(this.generatedSource.trim().length > 0 && !this.generating)
            .onClick(() => { this.doSave() })
        }
        .width('100%')
        .padding({ left: 16, right: 16 })

        Row({ space: 8 }) {
          Text(this.status)
            .fontSize(12)
            .fontColor(this.compiled ? '#34C759' : '#999999')
            .layoutWeight(1)
          Button(this.showCode ? 'Code ✓' : 'Code')
            .type(ButtonType.Normal)
            .fontSize(11)
            .height(28)
            .backgroundColor(this.showCode ? '#E8F0FE' : '#F0F0F0')
            .fontColor(this.showCode ? '#007DFF' : '#666666')
            .onClick(() => { this.showCode = !this.showCode })
          Button(this.showMetrics ? 'Metrics ✓' : 'Metrics')
            .type(ButtonType.Normal)
            .fontSize(11)
            .height(28)
            .backgroundColor(this.showMetrics ? '#E8F0FE' : '#F0F0F0')
            .fontColor(this.showMetrics ? '#007DFF' : '#666666')
            .onClick(() => { this.showMetrics = !this.showMetrics })
        }
        .width('100%')
        .padding({ left: 16, right: 16, top: 8, bottom: 4 })

        if (this.compileErrors.length > 0) {
          Scroll() {
            Text(this.compileErrors)
              .fontSize(11)
              .fontFamily('monospace')
              .fontColor('#FF3B30')
              .width('100%')
              .padding(8)
          }
          .width('100%')
          .constraintSize({ maxHeight: 120 })
          .margin({ left: 16, right: 16 })
          .backgroundColor('#FFF0F0')
          .borderRadius(8)
        }

        if (this.showMetrics && this.attempts.length > 0) {
          Column({ space: 6 }) {
            Row({ space: 16 }) {
              Text('Total: ' + this.formatMs(this.totalMs)).fontSize(12).fontWeight(FontWeight.Medium)
              if (this.mode !== MODE_SERVER) {
                Text('In: ' + this.totalInputTokens() + ' tok').fontSize(11).fontColor('#666666')
                Text('Out: ' + this.totalOutputTokens() + ' tok').fontSize(11).fontColor('#666666')
                if (this.totalCacheHitTokens() > 0) {
                  Text('cached: ' + this.totalCacheHitTokens()).fontSize(11).fontColor('#666666')
                }
              }
            }
            .width('100%')
            ForEach(this.attempts, (a: AttemptMetrics) => {
              Row({ space: 8 }) {
                Text('#' + a.attempt).fontSize(11).fontWeight(FontWeight.Medium).width(24)
                Text('gen ' + this.formatMs(a.genMs)).fontSize(10).fontColor('#666666')
                if (this.mode !== MODE_SERVER) {
                  Text('compile ' + this.formatMs(a.compileMs)).fontSize(10).fontColor('#666666')
                  Text(a.inputTokens + '→' + a.outputTokens).fontSize(10).fontColor('#666666')
                }
                Text(a.success ? '✓' : '✗')
                  .fontSize(12)
                  .fontColor(a.success ? '#34C759' : '#FF3B30')
              }
              .width('100%')
            })
          }
          .width('100%')
          .padding(12)
          .margin({ left: 16, right: 16, top: 4 })
          .backgroundColor('#F5F7FA')
          .borderRadius(8)
        }

        if (this.mode === MODE_LOCAL && !this.modelReady && !this.generating) {
          Column() {
            Text('Model not downloaded').fontSize(14).fontWeight(FontWeight.Medium)
            Text('Switch to Local mode to download the model automatically (one-time, ~1.9GB over WiFi).')
              .fontSize(12).fontColor('#666666').margin({ top: 4 })
          }
          .width('100%')
          .padding(16)
          .backgroundColor('#FFF8E0')
          .margin({ left: 16, right: 16, top: 8 })
          .borderRadius(8)
        }

        if (this.showCode) {
          Scroll() {
            Text(this.generatedSource.length > 0 ? this.generatedSource : '(generated source will appear here)')
              .fontSize(12)
              .fontFamily('monospace')
              .fontColor(this.generatedSource.length > 0 ? '#333333' : '#CCCCCC')
              .width('100%')
              .padding(12)
          }
          .width('100%')
          .layoutWeight(1)
          .margin({ left: 16, right: 16, top: 4, bottom: 16 })
          .backgroundColor('#F5F7FA')
          .borderRadius(8)
        }
      }
      .width('100%')
      .height('100%')
    }
    .title('Generate')
    .titleMode(NavigationTitleMode.Mini)
  }
}
