// The dealer agent harness behind NAPI (napi_dealer.cpp); DealerBridge.ets is its one user.
// Functions returning a string give '' on success and the reason otherwise.

/** False in a build without the dealer library (tools/build-dealer.sh); nothing else is defined then but dealerInit. */
export const dealerAvailable: () => boolean
/** Opens the session database once; `onSend(id, requestJson)` is asked to do each HTTP request. */
export const dealerInit: (dbPath: string, onSend: (id: number, requestJson: string) => void) => string
/** `{"id", "base_url", "path", "dialect": "deepseek" | "bearer", "key"}`, before any run. */
export const dealerRegisterProvider: (json: string) => string
/** The answer to request `id`: head once, chunks, then finish exactly once. */
export const dealerHead: (id: number, status: number, headersJson: string) => string
export const dealerChunk: (id: number, chunk: ArrayBuffer) => string
export const dealerFinish: (id: number, ok: boolean, message: string) => void
/** Whether dealer no longer wants request `id`'s answer. */
export const dealerCancelled: (id: number) => boolean
/** One turn in a new session, on a thread of its own; resolves with `{"finish_reason", "usage", "text"}`. */
export const dealerRun: (runId: number, sessionId: string, generationJson: string, contextJson: string,
  inputJson: string, onEvent: (eventJson: string) => void) => Promise<string>
export const dealerCancel: (runId: number) => void
/** A Jev decision through the same transport; resolves with Jev's answer body. */
export const dealerDecide: (endpoint: string, key: string, requestJson: string) => Promise<string>
