// The dealer agent harness (github.com/arkts-dev/dealer, crates/dealer-ffi) behind NAPI, for
// DealerBridge.ets. Dealer runs each turn on a thread of its own here, because
// dealer_session_run blocks; HTTP is done by ArkTS: dealer's transport callback hands the
// request to JS (dealerSend), and JS answers through dealerHead / dealerChunk / dealerFinish,
// which dealer.h allows from any thread. Without the library (tools/build-dealer.sh) this
// builds as a stub whose dealerAvailable() is false.

#include <napi/native_api.h>
#include <hilog/log.h>

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <mutex>
#include <string>
#include <thread>
#include <utility>

#ifndef DEALER_STUB
#include "dealer.h"
#endif

#undef LOG_DOMAIN
#undef LOG_TAG
#define LOG_DOMAIN 0x0000
#define LOG_TAG "VERA-DEALER"

namespace {

// --- Calls back to JS from any thread -------------------------------------------------------

struct Post {
    std::function<void(napi_env)> run;
};

void CallJs(napi_env env, napi_value /*js*/, void * /*context*/, void *data)
{
    std::unique_ptr<Post> post(static_cast<Post *>(data));
    if (env != nullptr) {
        post->run(env);
    }
}

napi_threadsafe_function MakeChannel(napi_env env, const char *name)
{
    napi_value resource = nullptr;
    napi_create_string_utf8(env, name, NAPI_AUTO_LENGTH, &resource);
    napi_threadsafe_function channel = nullptr;
    napi_create_threadsafe_function(env, nullptr, nullptr, resource, 0, 1, nullptr, nullptr, nullptr, CallJs,
                                    &channel);
    return channel;
}

bool PostTo(napi_threadsafe_function channel, std::function<void(napi_env)> run)
{
    auto *post = new Post{std::move(run)};  // NOLINT(cppcoreguidelines-owning-memory): owned by CallJs
    if (napi_call_threadsafe_function(channel, post, napi_tsfn_nonblocking) != napi_ok) {
        delete post;  // NOLINT(cppcoreguidelines-owning-memory)
        return false;
    }
    return true;
}

// --- Arguments ------------------------------------------------------------------------------

std::string StringArg(napi_env env, napi_value value)
{
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok) {
        return "";
    }
    std::string text(length, '\0');
    napi_get_value_string_utf8(env, value, text.data(), length + 1, &length);
    return text;
}

int64_t IntArg(napi_env env, napi_value value)
{
    int64_t number = 0;
    napi_get_value_int64(env, value, &number);
    return number;
}

napi_value String(napi_env env, const std::string &text)
{
    napi_value value = nullptr;
    napi_create_string_utf8(env, text.c_str(), text.size(), &value);
    return value;
}

napi_value Bool(napi_env env, bool flag)
{
    napi_value value = nullptr;
    napi_get_boolean(env, flag, &value);
    return value;
}

template <size_t N> size_t Args(napi_env env, napi_callback_info info, napi_value (&argv)[N])
{
    size_t argc = N;
    napi_get_cb_info(env, info, &argc, argv, nullptr, nullptr);
    return argc;
}

#ifndef DEALER_STUB

dealer_str Str(const std::string &text)
{
    return dealer_str{reinterpret_cast<const uint8_t *>(text.data()), text.size()};
}

std::string Take(dealer_error *error)
{
    std::string message = error != nullptr ? dealer_error_message(error) : "dealer failed";
    dealer_error_free(error);
    return message;
}

std::string Take(dealer_string text)
{
    std::string copy(reinterpret_cast<const char *>(text.ptr), text.len);
    dealer_string_free(text);
    return copy;
}

// --- The one instance this module runs -------------------------------------------------------

struct Module {
    std::mutex mutex;
    dealer_instance *instance = nullptr;
    napi_threadsafe_function send = nullptr;
    napi_ref onSend = nullptr;
    std::map<int64_t, dealer_exchange *> exchanges;
    int64_t nextExchange = 1;
    std::map<int64_t, dealer_cancel *> cancels;
};

Module &TheModule()
{
    // Never freed: the instance and its threads live as long as the process.
    static auto *module = new Module();  // NOLINT(cppcoreguidelines-owning-memory)
    return *module;
}

void Send(void * /*user*/, dealer_str request, dealer_exchange *exchange)
{
    Module &module = TheModule();
    int64_t id = 0;
    {
        std::lock_guard<std::mutex> lock(module.mutex);
        id = module.nextExchange++;
        module.exchanges[id] = exchange;
    }
    std::string json(reinterpret_cast<const char *>(request.ptr), request.len);
    bool posted = PostTo(module.send, [id, json](napi_env env) {
        napi_value fn = nullptr;
        napi_value undefined = nullptr;
        napi_get_reference_value(env, TheModule().onSend, &fn);
        napi_get_undefined(env, &undefined);
        napi_value argv[2] = {nullptr, nullptr};
        napi_create_int64(env, id, &argv[0]);
        argv[1] = String(env, json);
        napi_call_function(env, undefined, fn, 2, argv, nullptr);
    });
    if (!posted) {
        std::lock_guard<std::mutex> lock(module.mutex);
        module.exchanges.erase(id);
        dealer_exchange_finish(exchange, DEALER_INVALID_STATE, Str("The app could not take the request"));
    }
}

dealer_exchange *Exchange(int64_t id, bool remove)
{
    Module &module = TheModule();
    std::lock_guard<std::mutex> lock(module.mutex);
    auto found = module.exchanges.find(id);
    if (found == module.exchanges.end()) {
        return nullptr;
    }
    dealer_exchange *exchange = found->second;
    if (remove) {
        module.exchanges.erase(found);
    }
    return exchange;
}

// dealerInit(dbPath, onSend): '' or why not.
napi_value Init(napi_env env, napi_callback_info info)
{
    napi_value argv[2] = {nullptr, nullptr};
    if (Args(env, info, argv) < 2) {
        return String(env, "dealerInit takes a database path and a send callback");
    }
    Module &module = TheModule();
    std::lock_guard<std::mutex> lock(module.mutex);
    if (module.instance != nullptr) {
        return String(env, "");
    }
    napi_create_reference(env, argv[1], 1, &module.onSend);
    module.send = MakeChannel(env, "dealerSend");
    dealer_transport transport{sizeof(dealer_transport), nullptr, Send, nullptr};
    dealer_error *error = nullptr;
    std::string path = StringArg(env, argv[0]);
    if (dealer_instance_create(DEALER_ABI_VERSION, Str(path), &transport, &module.instance, &error) != DEALER_OK) {
        module.instance = nullptr;
        return String(env, Take(error));
    }
    OH_LOG_INFO(LOG_APP, "instance open, abi %{public}u", dealer_abi_version());
    return String(env, "");
}

// dealerRegisterProvider(json): '' or why not.
napi_value RegisterProvider(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    dealer_error *error = nullptr;
    std::string json = StringArg(env, argv[0]);
    if (dealer_instance_register_provider(TheModule().instance, Str(json), &error) != DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerHead(id, status, headersJson): '' or why not.
napi_value Head(napi_env env, napi_callback_info info)
{
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), false);
    if (exchange == nullptr) {
        return String(env, "No such exchange");
    }
    dealer_error *error = nullptr;
    std::string headers = StringArg(env, argv[2]);
    auto status = static_cast<uint16_t>(IntArg(env, argv[1]));
    if (dealer_exchange_head(exchange, status, Str(headers), &error) != DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerChunk(id, ArrayBuffer): '' or why not.
napi_value Chunk(napi_env env, napi_callback_info info)
{
    napi_value argv[2] = {nullptr, nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), false);
    void *data = nullptr;
    size_t length = 0;
    if (exchange == nullptr || napi_get_arraybuffer_info(env, argv[1], &data, &length) != napi_ok) {
        return String(env, "No such exchange, or the chunk is not an ArrayBuffer");
    }
    dealer_error *error = nullptr;
    if (dealer_exchange_chunk(exchange, dealer_str{static_cast<const uint8_t *>(data), length}, &error) !=
        DEALER_OK) {
        return String(env, Take(error));
    }
    return String(env, "");
}

// dealerFinish(id, ok, message): ends the exchange; dealer frees it.
napi_value Finish(napi_env env, napi_callback_info info)
{
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), true);
    bool ok = false;
    napi_get_value_bool(env, argv[1], &ok);
    std::string message = StringArg(env, argv[2]);
    if (exchange != nullptr) {
        dealer_exchange_finish(exchange, ok ? DEALER_OK : DEALER_INVALID_STATE, Str(message));
    }
    return nullptr;
}

// dealerCancelled(id): whether dealer no longer wants the answer.
napi_value Cancelled(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    dealer_exchange *exchange = Exchange(IntArg(env, argv[0]), false);
    return Bool(env, exchange == nullptr || dealer_exchange_is_cancelled(exchange));
}

// --- Runs and decisions, each on a thread of its own -----------------------------------------

/** A promise and an optional event callback, settled from a worker thread. */
struct Pending {
    napi_deferred deferred = nullptr;
    napi_ref onEvent = nullptr;
    napi_threadsafe_function channel = nullptr;

    void Settle(bool ok, std::string text)
    {
        napi_threadsafe_function channel = this->channel;
        PostTo(channel, [this, ok, text](napi_env env) {
            napi_value value = String(env, text);
            if (ok) {
                napi_resolve_deferred(env, deferred, value);
            } else {
                napi_value error = nullptr;
                napi_create_error(env, nullptr, value, &error);
                napi_reject_deferred(env, deferred, error);
            }
            if (onEvent != nullptr) {
                napi_delete_reference(env, onEvent);
            }
            delete this;  // NOLINT(cppcoreguidelines-owning-memory): the last use of this run
        });
        napi_release_threadsafe_function(channel, napi_tsfn_release);
    }
};

Pending *MakePending(napi_env env, napi_value onEvent, napi_value *promise)
{
    auto *pending = new Pending();  // NOLINT(cppcoreguidelines-owning-memory): freed by Settle
    napi_create_promise(env, &pending->deferred, promise);
    if (onEvent != nullptr) {
        napi_create_reference(env, onEvent, 1, &pending->onEvent);
    }
    pending->channel = MakeChannel(env, "dealerRun");
    return pending;
}

void OnEvent(void *user, dealer_str event)
{
    auto *pending = static_cast<Pending *>(user);
    if (pending->onEvent == nullptr) {
        return;
    }
    std::string json(reinterpret_cast<const char *>(event.ptr), event.len);
    napi_ref callback = pending->onEvent;
    PostTo(pending->channel, [callback, json](napi_env env) {
        napi_value fn = nullptr;
        napi_value undefined = nullptr;
        napi_get_reference_value(env, callback, &fn);
        napi_get_undefined(env, &undefined);
        napi_value argv[1] = {String(env, json)};
        napi_call_function(env, undefined, fn, 1, argv, nullptr);
    });
}

// dealerRun(runId, sessionId, generationJson, contextJson, inputJson, onEvent): Promise<resultJson>.
// A fresh session per run; its whole history stays in the database.
napi_value Run(napi_env env, napi_callback_info info)
{
    napi_value argv[6] = {nullptr, nullptr, nullptr, nullptr, nullptr, nullptr};
    Args(env, info, argv);
    int64_t runId = IntArg(env, argv[0]);
    std::string session = StringArg(env, argv[1]);
    std::string generation = StringArg(env, argv[2]);
    std::string context = StringArg(env, argv[3]);
    std::string input = StringArg(env, argv[4]);
    napi_value promise = nullptr;
    Pending *pending = MakePending(env, argv[5], &promise);
    dealer_cancel *cancel = dealer_cancel_new();
    {
        std::lock_guard<std::mutex> lock(TheModule().mutex);
        TheModule().cancels[runId] = cancel;
    }
    std::thread([pending, cancel, runId, session, generation, context, input]() {
        dealer_instance *instance = TheModule().instance;
        dealer_session *handle = nullptr;
        dealer_error *error = nullptr;
        dealer_observer observer{pending, OnEvent};
        dealer_string result{nullptr, 0};
        int32_t status = dealer_session_create(instance, Str(session), Str(generation), &handle, &error);
        if (status == DEALER_OK) {
            status = dealer_session_set_context(handle, Str(context), &error);
        }
        if (status == DEALER_OK) {
            status = dealer_session_start_turn(handle, Str(input), observer, &error);
        }
        if (status == DEALER_OK) {
            status = dealer_session_run(handle, cancel, observer, &result, &error);
        }
        dealer_session_free(handle);
        {
            std::lock_guard<std::mutex> lock(TheModule().mutex);
            TheModule().cancels.erase(runId);
        }
        dealer_cancel_free(cancel);
        if (status == DEALER_OK) {
            pending->Settle(true, Take(result));
        } else {
            std::string message = "dealer status " + std::to_string(status) + ": " + Take(error);
            OH_LOG_WARN(LOG_APP, "run %{public}s failed: %{public}s", session.c_str(), message.c_str());
            pending->Settle(false, message);
        }
    }).detach();
    return promise;
}

// dealerCancel(runId): stops a run; its promise rejects.
napi_value Cancel(napi_env env, napi_callback_info info)
{
    napi_value argv[1] = {nullptr};
    Args(env, info, argv);
    int64_t runId = IntArg(env, argv[0]);
    std::lock_guard<std::mutex> lock(TheModule().mutex);
    auto found = TheModule().cancels.find(runId);
    if (found != TheModule().cancels.end()) {
        dealer_cancel_trigger(found->second);
    }
    return nullptr;
}

// dealerDecide(endpoint, key, requestJson): Promise<answerJson>.
napi_value Decide(napi_env env, napi_callback_info info)
{
    napi_value argv[3] = {nullptr, nullptr, nullptr};
    Args(env, info, argv);
    std::string endpoint = StringArg(env, argv[0]);
    std::string key = StringArg(env, argv[1]);
    std::string request = StringArg(env, argv[2]);
    napi_value promise = nullptr;
    Pending *pending = MakePending(env, nullptr, &promise);
    std::thread([pending, endpoint, key, request]() {
        dealer_error *error = nullptr;
        dealer_string answer{nullptr, 0};
        int32_t status = dealer_decide(TheModule().instance, Str(endpoint), Str(key), Str(request), nullptr,
                                       &answer, &error);
        if (status == DEALER_OK) {
            pending->Settle(true, Take(answer));
        } else {
            std::string message = "dealer status " + std::to_string(status) + ": " + Take(error);
            OH_LOG_WARN(LOG_APP, "decide failed: %{public}s", message.c_str());
            pending->Settle(false, message);
        }
    }).detach();
    return promise;
}

napi_value Available(napi_env env, napi_callback_info /*info*/)
{
    return Bool(env, true);
}

#else  // DEALER_STUB

napi_value Unavailable(napi_env env, napi_callback_info /*info*/)
{
    return String(env, "This build has no dealer library (tools/build-dealer.sh)");
}

napi_value Available(napi_env env, napi_callback_info /*info*/)
{
    return Bool(env, false);
}

#endif

napi_value Register(napi_env env, napi_value exports)
{
#ifndef DEALER_STUB
    napi_property_descriptor desc[] = {
        {"dealerAvailable", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerInit", nullptr, Init, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerRegisterProvider", nullptr, RegisterProvider, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerHead", nullptr, Head, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerChunk", nullptr, Chunk, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerFinish", nullptr, Finish, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerCancelled", nullptr, Cancelled, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerRun", nullptr, Run, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerCancel", nullptr, Cancel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerDecide", nullptr, Decide, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
#else
    napi_property_descriptor desc[] = {
        {"dealerAvailable", nullptr, Available, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"dealerInit", nullptr, Unavailable, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
#endif
    if (napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc) != napi_ok) {
        OH_LOG_ERROR(LOG_APP, "cannot define the dealer functions");
    }
    return exports;
}

}  // namespace

EXTERN_C_START
// napi_module_register takes a non-const pointer and keeps it.
static napi_module g_module = {  // NOLINT(cppcoreguidelines-avoid-non-const-global-variables)
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Register,
    .nm_modname = "dealer",
    .nm_priv = nullptr,
    .reserved = {nullptr},
};

__attribute__((constructor)) void RegisterDealer(void)
{
    napi_module_register(&g_module);
}
EXTERN_C_END
