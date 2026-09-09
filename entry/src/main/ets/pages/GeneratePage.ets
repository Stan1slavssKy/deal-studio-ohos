import router from '@ohos.router'
import fs from '@ohos.file.fs'
import { store } from '../vera/ProjectStore'
import { engine, LlamaEngine, GenerateRequest, loadRawfileText } from '../vera/LlamaEngine'
import { compileVeraSource, CompileError } from '../vera/VeraCompiler'

const MAX_RETRIES: number = 3

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
  private systemPrompt: string = ''
  private grammar: string = ''
  private previousSource: string = ''

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
    this.status = 'Generating (attempt 1/' + MAX_RETRIES + ')...'
    this.runAttempt(this.prompt.trim(), '')
  }

  private runAttempt(userPrompt: string, errorFeedback: string): void {
    this.generatedSource = ''
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

    try {
      let result = engine.generate(request, (token: string) => {
        this.generatedSource += token
      })
      if (result.length > 0) {
        this.generatedSource = result
      }
    } catch (e) {
      this.status = 'Generation failed: ' + (e as Error).message
      this.generating = false
      return
    }

    if (this.generatedSource.trim().length === 0) {
      this.status = 'Generation produced empty output'
      this.generating = false
      return
    }

    this.status = 'Compiling (attempt ' + this.attempt + '/' + MAX_RETRIES + ')...'
    let vbc2 = ''
    let errors = ''
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

    if (errors.length === 0 && vbc2.length > 0) {
      this.compiled = true
      this.compileErrors = ''
      this.status = 'Compiled successfully on attempt ' + this.attempt
      this.generating = false
      return
    }

    this.compileErrors = errors
    if (this.attempt < MAX_RETRIES) {
      this.attempt++
      this.status = 'Compile failed, retrying (attempt ' + this.attempt + '/' + MAX_RETRIES + ')...'
      this.runAttempt(userPrompt, errors)
    } else {
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

        Text(this.status)
          .fontSize(12)
          .fontColor(this.compiled ? '#34C759' : '#999999')
          .padding({ left: 16, top: 8, bottom: 4 })
          .width('100%')

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
        .margin({ left: 16, right: 16, top: 8, bottom: 16 })
        .backgroundColor('#F5F7FA')
        .borderRadius(8)
      }
      .width('100%')
      .height('100%')
    }
    .title('Generate')
    .titleMode(NavigationTitleMode.Mini)
  }
}
