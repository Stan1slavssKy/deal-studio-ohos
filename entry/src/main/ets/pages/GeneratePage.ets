import router from '@ohos.router'
import fs from '@ohos.file.fs'
import { store } from '../vera/ProjectStore'
import { engine, LlamaEngine, GenerateRequest, GenerateResult, loadRawfileText } from '../vera/LlamaEngine'
import { compileVeraSource, CompileError } from '../vera/VeraCompiler'

const MAX_RETRIES: number = 3

class AttemptMetrics {
  attempt: number = 0
  genMs: number = 0
  compileMs: number = 0
  inputTokens: number = 0
  outputTokens: number = 0
  success: boolean = false
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
    this.loadResources()
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
    this.checkModel()
  }

  private checkModel(): void {
    let filesDir = getContext(this).filesDir
    let modelPath = LlamaEngine.defaultModelPath(filesDir)
    try {
      let stat = fs.statSync(modelPath)
      this.modelReady = stat.size > 0
      if (this.modelReady) {
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
      } else {
        this.status = 'Model not found'
      }
    } catch (_e) {
      this.modelReady = false
      this.status = 'Model not found at ' + modelPath
    }
  }

  private doGenerate(): void {
    if (!this.modelReady || this.prompt.trim().length === 0) { return }
    this.generating = true
    this.generatedSource = ''
    this.compiled = false
    this.compileErrors = ''
    this.attempt = 1
    this.attempts = []
    this.totalMs = 0
    this.genStartTime = Date.now()
    this.status = 'Generating (attempt 1/' + MAX_RETRIES + ')...'
    this.runAttempt(this.prompt.trim(), '')
  }

  private runAttempt(userPrompt: string, errorFeedback: string): void {
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
      genResult = engine.generate(request, (token: string) => {
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
    metrics.inputTokens = genResult.inputTokens
    metrics.outputTokens = genResult.outputTokens

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
      this.runAttempt(userPrompt, errors)
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
    if (this.compiled) {
      try {
        let result = compileVeraSource(this.generatedSource.trim())
        vbc2 = result.vbc2
      } catch (_e) {}
    }
    store.createVersion(this.projectId, this.generatedSource.trim(), vbc2, note)
    this.status = vbc2.length > 0 ? 'Saved with compiled bytecode' : 'Saved (source only — compile errors)'
    router.back()
  }

  private formatMs(ms: number): string {
    if (ms < 1000) return ms + 'ms'
    let secs = (ms / 1000).toFixed(1)
    return secs + 's'
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

        TextArea({ placeholder: 'Describe the app you want...', text: this.prompt })
          .onChange((value: string) => { this.prompt = value })
          .width('100%')
          .height(100)
          .margin(16)

        Row({ space: 10 }) {
          Button(this.generating ? 'Stop' : 'Generate')
            .type(ButtonType.Normal)
            .layoutWeight(1)
            .enabled(this.modelReady || this.generating)
            .onClick(() => {
              if (this.generating) {
                engine.stop()
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
              Text('In: ' + this.totalInputTokens() + ' tok').fontSize(11).fontColor('#666666')
              Text('Out: ' + this.totalOutputTokens() + ' tok').fontSize(11).fontColor('#666666')
            }
            .width('100%')
            ForEach(this.attempts, (a: AttemptMetrics) => {
              Row({ space: 8 }) {
                Text('#' + a.attempt).fontSize(11).fontWeight(FontWeight.Medium).width(24)
                Text('gen ' + this.formatMs(a.genMs)).fontSize(10).fontColor('#666666')
                Text('compile ' + this.formatMs(a.compileMs)).fontSize(10).fontColor('#666666')
                Text(a.inputTokens + '→' + a.outputTokens).fontSize(10).fontColor('#666666')
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

        if (!this.modelReady && !this.generating) {
          Column() {
            Text('Model not found').fontSize(14).fontWeight(FontWeight.Medium)
            Text('Place Qwen3-Coder-3B GGUF at:').fontSize(12).fontColor('#666666').margin({ top: 4 })
            Text(LlamaEngine.defaultModelPath(getContext(this).filesDir))
              .fontSize(11).fontColor('#999999').margin({ top: 2 })
              .maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
            Text('hdc file send <model>.gguf <path above>').fontSize(11).fontColor('#007DFF').margin({ top: 4 })
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
