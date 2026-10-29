/*
 * Copyright (c) 2026 hxxalpha
 * SPDX-License-Identifier: MIT
 *
 * A native x64 IExplorerCommand. Reads selected paths and writes Unicode text
 * to the clipboard; it does not read file contents or launch another process.
 */
#define UNICODE
#define _UNICODE
#include <windows.h>
#include <guiddef.h>
#include <wchar.h>
#include <string.h>
#include <stdlib.h>

__declspec(dllimport) LANGID WINAPI GetUserDefaultUILanguage(void);
__declspec(dllimport) void *WINAPI CoTaskMemAlloc(SIZE_T size);
__declspec(dllimport) void WINAPI CoTaskMemFree(void *memory);

static const GUID CLSID_CopyPath = {0xce06539d,0x2b11,0x4f45,{0x8c,0x71,0x62,0x2b,0x8a,0x73,0xad,0x38}};
static const GUID ID_Unknown = {0,0,0,{0xc0,0,0,0,0,0,0,0x46}};
static const GUID ID_Factory = {1,0,0,{0xc0,0,0,0,0,0,0,0x46}};
static const GUID ID_Command = {0xa08ce4d0,0xfa25,0x44ab,{0xb5,0x7c,0xc7,0xb1,0xc3,0x23,0xe0,0xb9}};
static LONG objectCount = 0;
static LONG serverLocks = 0;
static HINSTANCE moduleInstance;

/* ABI-compatible shell interface slots. Keep their order unchanged. */
typedef struct ShellItem ShellItem;
typedef struct ShellArray ShellArray;
typedef struct ShellItemVTable {
    void *query, *addref;
    ULONG (WINAPI *release)(ShellItem *);
    void *bind, *parent;
    HRESULT (WINAPI *displayName)(ShellItem *, UINT, WCHAR **);
    void *attributes, *compare;
} ShellItemVTable;
struct ShellItem { ShellItemVTable *vtable; };
typedef struct ShellArrayVTable {
    void *query, *addref, *release, *bind, *properties, *description, *attributes;
    HRESULT (WINAPI *count)(ShellArray *, DWORD *);
    HRESULT (WINAPI *itemAt)(ShellArray *, DWORD, ShellItem **);
    void *enumerate;
} ShellArrayVTable;
struct ShellArray { ShellArrayVTable *vtable; };

typedef struct Command Command;
typedef struct CommandVTable {
    HRESULT (WINAPI *query)(Command *, const GUID *, void **);
    ULONG (WINAPI *addref)(Command *);
    ULONG (WINAPI *release)(Command *);
    HRESULT (WINAPI *title)(Command *, ShellArray *, WCHAR **);
    HRESULT (WINAPI *icon)(Command *, ShellArray *, WCHAR **);
    HRESULT (WINAPI *tooltip)(Command *, ShellArray *, WCHAR **);
    HRESULT (WINAPI *name)(Command *, GUID *);
    HRESULT (WINAPI *state)(Command *, ShellArray *, BOOL, DWORD *);
    HRESULT (WINAPI *invoke)(Command *, ShellArray *, void *);
    HRESULT (WINAPI *flags)(Command *, DWORD *);
    HRESULT (WINAPI *subcommands)(Command *, void **);
} CommandVTable;
struct Command { CommandVTable *vtable; LONG references; };

static int guidEqual(const GUID *left, const GUID *right) {
    return left && right && memcmp(left, right, sizeof(GUID)) == 0;
}
static HRESULT duplicateText(const WCHAR *text, WCHAR **result) {
    SIZE_T bytes;
    if (!result) return E_POINTER;
    *result = NULL;
    bytes = (wcslen(text) + 1) * sizeof(WCHAR);
    *result = CoTaskMemAlloc(bytes);
    if (!*result) return E_OUTOFMEMORY;
    memcpy(*result, text, bytes);
    return S_OK;
}

/* Leave the clipboard untouched if any selected item has no filesystem path. */
static HRESULT collectSelectionText(ShellArray *items, WCHAR **result) {
    DWORD count = 0, index;
    SIZE_T total = 1, length, offset = 0;
    WCHAR **paths = NULL, *text = NULL;
    HRESULT status;
    if (!result) return E_POINTER;
    *result = NULL;
    if (!items) return E_INVALIDARG;
    status = items->vtable->count(items, &count);
    if (FAILED(status) || !count) return FAILED(status) ? status : E_INVALIDARG;
    if (count > 100000) return E_INVALIDARG;
    paths = calloc(count, sizeof(WCHAR *));
    if (!paths) return E_OUTOFMEMORY;
    for (index = 0; index < count; ++index) {
        ShellItem *item = NULL;
        status = items->vtable->itemAt(items, index, &item);
        if (FAILED(status) || !item) { status = FAILED(status) ? status : E_FAIL; goto done; }
        status = item->vtable->displayName(item, 0x80058000U, &paths[index]); /* SIGDN_FILESYSPATH */
        item->vtable->release(item);
        if (FAILED(status) || !paths[index]) { status = FAILED(status) ? status : E_FAIL; goto done; }
        length = wcslen(paths[index]);
        if (length > 32767 || total > 32 * 1024 * 1024 - length - 2) { status = E_OUTOFMEMORY; goto done; }
        total += length + (index ? 2 : 0);
    }
    text = CoTaskMemAlloc(total * sizeof(WCHAR));
    if (!text) { status = E_OUTOFMEMORY; goto done; }
    for (index = 0; index < count; ++index) {
        if (index) { text[offset++] = L'\r'; text[offset++] = L'\n'; }
        length = wcslen(paths[index]);
        memcpy(text + offset, paths[index], length * sizeof(WCHAR));
        offset += length;
    }
    text[offset] = 0;
    *result = text;
    status = S_OK;
done:
    for (index = 0; index < count; ++index) if (paths[index]) CoTaskMemFree(paths[index]);
    free(paths);
    return status;
}
static ULONG WINAPI commandAddRef(Command *self) { return InterlockedIncrement(&self->references); }
static ULONG WINAPI commandRelease(Command *self) {
    LONG remaining = InterlockedDecrement(&self->references);
    if (!remaining) { free(self); InterlockedDecrement(&objectCount); }
    return remaining;
}
static HRESULT WINAPI commandQuery(Command *self, const GUID *id, void **result) {
    if (!result) return E_POINTER;
    *result = NULL;
    if (!guidEqual(id, &ID_Unknown) && !guidEqual(id, &ID_Command)) return E_NOINTERFACE;
    *result = self;
    commandAddRef(self);
    return S_OK;
}
static HRESULT WINAPI commandTitle(Command *self, ShellArray *items, WCHAR **result) {
    if (PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE)
        return duplicateText(L"\u590d\u5236\u7edd\u5bf9\u8def\u5f84", result);
    return duplicateText(L"Copy absolute path", result);
}
static HRESULT WINAPI commandIcon(Command *self, ShellArray *items, WCHAR **result) {
    if (!result) return E_POINTER;
    *result = NULL;
    return E_NOTIMPL;
}
static HRESULT WINAPI commandTooltip(Command *self, ShellArray *items, WCHAR **result) {
    if (PRIMARYLANGID(GetUserDefaultUILanguage()) == LANG_CHINESE)
        return duplicateText(L"\u590d\u5236\u5b8c\u6574\u8def\u5f84\uff08\u4e0d\u5e26\u5f15\u53f7\uff09", result);
    return duplicateText(L"Copy full paths without quotation marks", result);
}
static HRESULT WINAPI commandName(Command *self, GUID *name) {
    if (!name) return E_POINTER;
    *name = CLSID_CopyPath;
    return S_OK;
}
static HRESULT WINAPI commandState(Command *self, ShellArray *items, BOOL slow, DWORD *state) {
    DWORD count = 0;
    if (!state) return E_POINTER;
    *state = 2; /* ECS_HIDDEN */
    if (items && SUCCEEDED(items->vtable->count(items, &count)) && count) *state = 0;
    return S_OK;
}
static HRESULT WINAPI commandInvoke(Command *self, ShellArray *items, void *context) {
    WCHAR *text = NULL, *output;
    HGLOBAL memory = NULL;
    HWND owner = NULL;
    DWORD attempts;
    SIZE_T bytes;
    HRESULT status = collectSelectionText(items, &text);
    if (FAILED(status)) return status;
    bytes = (wcslen(text) + 1) * sizeof(WCHAR);
    memory = GlobalAlloc(GMEM_MOVEABLE, bytes);
    if (!memory) { status = E_OUTOFMEMORY; goto done; }
    output = GlobalLock(memory);
    if (!output) { status = E_FAIL; goto done; }
    memcpy(output, text, bytes);
    GlobalUnlock(memory);
    /* Use an invisible top-level window: message-only owners are unreliable. */
    owner = CreateWindowExW(0, L"STATIC", L"CopyAbsolutePath", WS_POPUP,
        0, 0, 0, 0, NULL, NULL, moduleInstance, NULL);
    if (!owner) { status = HRESULT_FROM_WIN32(GetLastError()); goto done; }
    for (attempts = 0; attempts < 10; ++attempts) {
        if (OpenClipboard(owner)) break;
        Sleep(20);
    }
    if (attempts == 10) { status = HRESULT_FROM_WIN32(ERROR_ACCESS_DENIED); goto done; }
    if (!EmptyClipboard() || !SetClipboardData(CF_UNICODETEXT, memory)) {
        status = HRESULT_FROM_WIN32(GetLastError());
        if (SUCCEEDED(status)) status = E_FAIL;
    } else { memory = NULL; status = S_OK; }
    CloseClipboard();
done:
    if (owner) DestroyWindow(owner);
    if (memory) GlobalFree(memory);
    CoTaskMemFree(text);
    return status;
}
static HRESULT WINAPI commandFlags(Command *self, DWORD *flags) {
    if (!flags) return E_POINTER;
    *flags = 0;
    return S_OK;
}
static HRESULT WINAPI commandSubcommands(Command *self, void **result) {
    if (!result) return E_POINTER;
    *result = NULL;
    return E_NOTIMPL;
}
static CommandVTable commandVTable = {
    commandQuery, commandAddRef, commandRelease, commandTitle, commandIcon,
    commandTooltip, commandName, commandState, commandInvoke, commandFlags,
    commandSubcommands
};

typedef struct Factory Factory;
typedef struct FactoryVTable {
    HRESULT (WINAPI *query)(Factory *, const GUID *, void **);
    ULONG (WINAPI *addref)(Factory *);
    ULONG (WINAPI *release)(Factory *);
    HRESULT (WINAPI *create)(Factory *, void *, const GUID *, void **);
    HRESULT (WINAPI *lock)(Factory *, BOOL);
} FactoryVTable;
struct Factory { FactoryVTable *vtable; LONG references; };
static ULONG WINAPI factoryAddRef(Factory *self) { return InterlockedIncrement(&self->references); }
static ULONG WINAPI factoryRelease(Factory *self) {
    LONG remaining = InterlockedDecrement(&self->references);
    if (!remaining) { free(self); InterlockedDecrement(&objectCount); }
    return remaining;
}
static HRESULT WINAPI factoryQuery(Factory *self, const GUID *id, void **result) {
    if (!result) return E_POINTER;
    *result = NULL;
    if (!guidEqual(id, &ID_Unknown) && !guidEqual(id, &ID_Factory)) return E_NOINTERFACE;
    *result = self;
    factoryAddRef(self);
    return S_OK;
}
static HRESULT WINAPI factoryCreate(Factory *self, void *outer, const GUID *id, void **result) {
    Command *command;
    HRESULT status;
    if (!result) return E_POINTER;
    *result = NULL;
    if (outer) return CLASS_E_NOAGGREGATION;
    command = calloc(1, sizeof(Command));
    if (!command) return E_OUTOFMEMORY;
    command->vtable = &commandVTable;
    command->references = 1;
    InterlockedIncrement(&objectCount);
    status = commandQuery(command, id, result);
    commandRelease(command);
    return status;
}
static HRESULT WINAPI factoryLock(Factory *self, BOOL lock) {
    if (lock) InterlockedIncrement(&serverLocks); else InterlockedDecrement(&serverLocks);
    return S_OK;
}
static FactoryVTable factoryVTable = {
    factoryQuery, factoryAddRef, factoryRelease, factoryCreate, factoryLock
};
__declspec(dllexport) HRESULT WINAPI DllGetClassObject(const GUID *classId, const GUID *id, void **result) {
    Factory *factory;
    HRESULT status;
    if (!result) return E_POINTER;
    *result = NULL;
    if (!guidEqual(classId, &CLSID_CopyPath)) return CLASS_E_CLASSNOTAVAILABLE;
    factory = calloc(1, sizeof(Factory));
    if (!factory) return E_OUTOFMEMORY;
    factory->vtable = &factoryVTable;
    factory->references = 1;
    InterlockedIncrement(&objectCount);
    status = factoryQuery(factory, id, result);
    factoryRelease(factory);
    return status;
}
__declspec(dllexport) HRESULT WINAPI DllCanUnloadNow(void) {
    return !objectCount && !serverLocks ? S_OK : S_FALSE;
}
#ifdef COPY_PATH_TESTING
/* Included only in the test DLL, never in the installed extension. */
__declspec(dllexport) HRESULT WINAPI CopyPathTestBuildSelectionText(ShellArray *items, WCHAR **result) {
    return collectSelectionText(items, result);
}
#endif
BOOL WINAPI DllMain(HINSTANCE instance, DWORD reason, LPVOID reserved) {
    if (reason == DLL_PROCESS_ATTACH) {
        moduleInstance = instance;
        DisableThreadLibraryCalls(instance);
    }
    return TRUE;
}
