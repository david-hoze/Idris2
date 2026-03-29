#include <stdbool.h>
#ifdef _WIN32
#include <windows.h>
#endif

#include "_datatypes.h"
#include "refc_util.h"
#include "runtime.h"


/* ---- live-object diagnostics ----
 * Tracks: allocations, frees, live count, high-water mark,
 * and per-tag breakdown of currently live objects.
 * Auto-reports every REPORT_INTERVAL allocations to stderr.
 */
#define IDRIS2_MEMSTAT_ENABLED 0
#define REPORT_INTERVAL 500000000

#if IDRIS2_MEMSTAT_ENABLED
static struct {
  uint64_t n_alloc;
  uint64_t n_freed;
  uint64_t n_live;
  uint64_t n_live_peak;
  uint64_t n_immortalized;
  uint64_t bytes_alloc;
  uint64_t bytes_freed;
  /* per-tag live counts (tags 0-31) */
  uint64_t tag_live[32];
} idris2_ms = {0};

#define IDRIS2_INC_MEMSTAT(x)

static void idris2_memstat_alloc(size_t sz) {
  idris2_ms.n_alloc++;
  idris2_ms.n_live++;
  idris2_ms.bytes_alloc += sz;
  if (idris2_ms.n_live > idris2_ms.n_live_peak)
    idris2_ms.n_live_peak = idris2_ms.n_live;
  if (idris2_ms.n_alloc % REPORT_INTERVAL == 0) {
    fprintf(stderr,
      "[MEMSTAT] alloc=%llu freed=%llu live=%llu peak=%llu "
      "bytes_net=%.1fMB immortal=%llu "
      "| clos=%llu ctor=%llu str=%llu int=%llu ioref=%llu arr=%llu\n",
      (unsigned long long)idris2_ms.n_alloc,
      (unsigned long long)idris2_ms.n_freed,
      (unsigned long long)idris2_ms.n_live,
      (unsigned long long)idris2_ms.n_live_peak,
      (double)(idris2_ms.bytes_alloc - idris2_ms.bytes_freed) / (1024.0*1024.0),
      (unsigned long long)idris2_ms.n_immortalized,
      (unsigned long long)idris2_ms.tag_live[CLOSURE_TAG],
      (unsigned long long)idris2_ms.tag_live[CONSTRUCTOR_TAG],
      (unsigned long long)idris2_ms.tag_live[STRING_TAG],
      (unsigned long long)idris2_ms.tag_live[INTEGER_TAG],
      (unsigned long long)idris2_ms.tag_live[IOREF_TAG],
      (unsigned long long)idris2_ms.tag_live[ARRAY_TAG]);
  }
}

static void idris2_memstat_tag_inc(uint8_t tag) {
  if (tag < 32) idris2_ms.tag_live[tag]++;
}

static void idris2_memstat_free(Value *p, size_t sz) {
  idris2_ms.n_freed++;
  if (idris2_ms.n_live > 0) idris2_ms.n_live--;
  idris2_ms.bytes_freed += sz;
  uint8_t tag = p->header.tag;
  if (tag < 32 && idris2_ms.tag_live[tag] > 0)
    idris2_ms.tag_live[tag]--;
}

void idris2_dumpMemoryStats(void) {
  fprintf(stderr,
    "[MEMSTAT FINAL] alloc=%llu freed=%llu live=%llu peak=%llu "
    "bytes_net=%.1fMB immortal=%llu\n",
    (unsigned long long)idris2_ms.n_alloc,
    (unsigned long long)idris2_ms.n_freed,
    (unsigned long long)idris2_ms.n_live,
    (unsigned long long)idris2_ms.n_live_peak,
    (double)(idris2_ms.bytes_alloc - idris2_ms.bytes_freed) / (1024.0*1024.0),
    (unsigned long long)idris2_ms.n_immortalized);
}

#else
#define IDRIS2_INC_MEMSTAT(x)
static inline void idris2_memstat_alloc(size_t sz) { (void)sz; }
static inline void idris2_memstat_tag_inc(uint8_t tag) { (void)tag; }
static inline void idris2_memstat_free(Value *p, size_t sz) { (void)p; (void)sz; }
void idris2_dumpMemoryStats() {}
#endif

/* Slow path for newReference — called only for heap objects. */
Value *idris2_newReference_slow(Value *source) {
  if (source->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX) {
#if IDRIS2_MEMSTAT_ENABLED
    idris2_ms.n_immortalized++;
#endif
  } else {
    source->header.refCounter++;
  }
  return source;
}

/* ---- pymalloc-inspired arena pool allocator ----
 *
 * Three-level structure (like CPython's pymalloc):
 *   Arena (64 KB)  →  contains blocks of one size class
 *   Free list      →  per size class, capped at POOL_FREELIST_MAX
 *   Overflow       →  blocks beyond the cap are returned to free()
 *
 * Size classes: 16, 24, 32, 48, 64, 80, 96, 128 bytes.
 * Pool index (1-8) stored in header.reserved for O(1) dealloc routing.
 *
 * Key improvements over simple malloc/free:
 *   - Arena blocks are contiguous → better cache locality
 *   - Free list reuse avoids malloc/free overhead
 *   - Cap prevents unbounded memory growth
 */
#define POOL_NUM_CLASSES    8
#define POOL_FREELIST_MAX   1024  /* max free blocks per size class */
#define ARENA_SIZE          65536 /* 64 KB arenas */

static void *pool_free[POOL_NUM_CLASSES] = {0};
static int   pool_free_count[POOL_NUM_CLASSES] = {0};
static const size_t pool_sizes[POOL_NUM_CLASSES] = {16,24,32,48,64,80,96,128};

/* (arena allocation disabled — causes MSYS2 exit code 127) */

/* Map byte size -> pool index (0-7), or -1 for oversized. */
static inline int pool_index(size_t sz) {
  if (sz <= 16)  return 0;
  if (sz <= 24)  return 1;
  if (sz <= 32)  return 2;
  if (sz <= 48)  return 3;
  if (sz <= 64)  return 4;
  if (sz <= 80)  return 5;
  if (sz <= 96)  return 6;
  if (sz <= 128) return 7;
  return -1;
}

/* Flush all pool freelists back to the OS, freeing cached memory. */
static void pool_flush_all(void) {
  for (int i = 0; i < POOL_NUM_CLASSES; i++) {
    void *p = pool_free[i];
    while (p) {
      void *next = *(void **)p;
      free(p);
      p = next;
    }
    pool_free[i] = NULL;
    pool_free_count[i] = 0;
  }
#if defined(__GLIBC__)
  malloc_trim(0);  /* return freed pages to OS */
#elif defined(_WIN32)
  HeapCompact(GetProcessHeap(), 0);
#endif
}

Value *idris2_newValue(size_t size) {
  int idx = pool_index(size);
  Value *retVal;
  if (idx >= 0 && pool_free_count[idx] > 0) {
    retVal = (Value *)pool_free[idx];
    pool_free[idx] = *(void **)pool_free[idx];
    --pool_free_count[idx];
  } else {
    size_t real = (idx >= 0) ? pool_sizes[idx] : size;
    retVal = (Value *)malloc(real);
    /* On malloc failure, flush all pool freelists and retry once. */
    if (!retVal) {
      pool_flush_all();
      retVal = (Value *)malloc(real);
    }
  }
  IDRIS2_REFC_VERIFY(retVal && !idris2_vp_is_unboxed(retVal), "malloc failed");
  idris2_memstat_alloc((idx >= 0) ? pool_sizes[idx] : size);
  retVal->header.refCounter = 1;
  { static uint64_t _alloc_ctr = 0;
    if (++_alloc_ctr % 50000000 == 0) idris2_log_rss("alloc");
  }
  retVal->header.tag = NO_TAG;
  retVal->header.reserved = (uint8_t)(idx >= 0 ? idx + 1 : 0);
  return retVal;
}

/* Return a block to its pool, or free() if oversized or pool is full. */
void idris2_pool_dealloc(Value *p) {
  uint8_t cls = p->header.reserved;
  size_t sz = (cls >= 1 && cls <= POOL_NUM_CLASSES)
    ? pool_sizes[cls - 1]
    : sizeof(Value);  /* approximate for oversized */
  idris2_memstat_free(p, sz);
  if (cls >= 1 && cls <= POOL_NUM_CLASSES) {
    int idx = cls - 1;
    if (pool_free_count[idx] < POOL_FREELIST_MAX) {
      *(void **)p = pool_free[idx];
      pool_free[idx] = p;
      ++pool_free_count[idx];
    } else {
      free(p);
    }
  } else {
    free(p);
  }
}

Value_Constructor *idris2_newConstructor(int total, int tag) {
  Value_Constructor *retVal = (Value_Constructor *)idris2_newValue(
      sizeof(Value_Constructor) + sizeof(Value *) * total);
  retVal->header.tag = CONSTRUCTOR_TAG;
  idris2_memstat_tag_inc(CONSTRUCTOR_TAG);
  retVal->total = total;
  retVal->tag = tag;
  retVal->name = NULL;
  /* Zero-initialize args: codegen emits idris2_removeReference on all args
     even for freshly allocated constructors (not just reused ones).
     Without this, the cleanup loop dereferences garbage pointers. */
  memset(retVal->args, 0, sizeof(Value *) * total);
  return retVal;
}

Value_Closure *idris2_mkClosure(Value *(*f)(), uint8_t arity, uint8_t filled) {
  Value_Closure *retVal = (Value_Closure *)idris2_newValue(
      sizeof(Value_Closure) + sizeof(Value *) * filled);
  retVal->header.tag = CLOSURE_TAG;
  idris2_memstat_tag_inc(CLOSURE_TAG);
  retVal->f = f;
  retVal->arity = arity;
  retVal->filled = filled;
  return retVal; // caller must initialize args[].
}

/* idris2_mkDouble is now static inline in memoryManagement.h */

Value *idris2_mkBits32_Boxed(uint32_t i) {
  Value_Bits32 *retVal = IDRIS2_NEW_VALUE(Value_Bits32);
  retVal->header.tag = BITS32_TAG;
  retVal->ui32 = i;
  return (Value *)retVal;
}

Value *idris2_mkBits64(uint64_t i) {
  if (i < 100)
    return (Value *)&idris2_predefined_Bits64[i];

  Value_Bits64 *retVal = IDRIS2_NEW_VALUE(Value_Bits64);
  retVal->header.tag = BITS64_TAG;
  retVal->ui64 = i;
  return (Value *)retVal;
}

Value *idris2_mkInt32_Boxed(int32_t i) {
  Value_Int32 *retVal = IDRIS2_NEW_VALUE(Value_Int32);
  retVal->header.tag = INT32_TAG;
  retVal->i32 = i;
  return (Value *)retVal;
}

Value *idris2_mkInt64(int64_t i) {
  if (i >= 0 && i < 100)
    return (Value *)&idris2_predefined_Int64[i];

  Value_Int64 *retVal = IDRIS2_NEW_VALUE(Value_Int64);
  retVal->header.tag = INT64_TAG;
  retVal->i64 = i;
  return (Value *)retVal;
}

Value_Integer *idris2_mkInteger() {
  Value_Integer *retVal = IDRIS2_NEW_VALUE(Value_Integer);
  retVal->header.tag = INTEGER_TAG;
  mpz_init(retVal->i);
  return retVal;
}

Value *idris2_mkIntegerLiteral(char *i) {
  if (sizeof(uintptr_t) >= 8) {
    char *end;
    long long v = strtoll(i, &end, 10);
    if (*end == '\0' && IDRIS2_FITS_FIXNUM((int64_t)v))
      return IDRIS2_MKFIXNUM((int64_t)v);
  }
  Value_Integer *retVal = idris2_mkInteger();
  mpz_set_str(retVal->i, i, 10);
  return (Value *)retVal;
}

Value_String *idris2_mkEmptyString(size_t l) {
  if (l == 1)
    return (Value_String *)&idris2_predefined_nullstring;

  Value_String *retVal = IDRIS2_NEW_VALUE(Value_String);
  retVal->header.tag = STRING_TAG;
  idris2_memstat_tag_inc(STRING_TAG);
  retVal->str = malloc(l);
  memset(retVal->str, 0, l);
  return retVal;
}

Value_String *idris2_mkString(char *s) {
  if (s[0] == '\0')
    return (Value_String *)&idris2_predefined_nullstring;

  Value_String *retVal = IDRIS2_NEW_VALUE(Value_String);
  int l = strlen(s);
  retVal->header.tag = STRING_TAG;
  idris2_memstat_tag_inc(STRING_TAG);
  retVal->str = malloc(l + 1);
  memset(retVal->str, 0, l + 1);
  memcpy(retVal->str, s, l);
  return retVal;
}

Value_Pointer *idris2_makePointer(void *ptr_Raw) {
  Value_Pointer *p = IDRIS2_NEW_VALUE(Value_Pointer);
  p->header.tag = POINTER_TAG;
  p->p = ptr_Raw;
  return p;
}

Value_GCPointer *idris2_makeGCPointer(void *ptr_Raw,
                                      Value_Closure *onCollectFct) {
  Value_GCPointer *p = IDRIS2_NEW_VALUE(Value_GCPointer);
  p->header.tag = GC_POINTER_TAG;
  p->p = idris2_makePointer(ptr_Raw);
  p->onCollectFct = onCollectFct;
  return p;
}

Value_Buffer *idris2_makeBuffer(void *buf) {
  Value_Buffer *b = IDRIS2_NEW_VALUE(Value_Buffer);
  b->header.tag = BUFFER_TAG;
  b->buffer = buf;
  return b;
}

Value_Array *idris2_makeArray(int length) {
  Value_Array *a = IDRIS2_NEW_VALUE(Value_Array);
  a->header.tag = ARRAY_TAG;
  a->capacity = length;
  a->arr = (Value **)malloc(sizeof(Value *) * length);
  memset(a->arr, 0, sizeof(Value *) * length);
  return a;
}

/* Slow path for removeReference — called only for heap objects. */
void idris2_removeReference_slow(Value *elem) {
  IDRIS2_INC_MEMSTAT(n_removeReference);
  if (elem->header.refCounter == IDRIS2_VP_REFCOUNTER_MAX) {
    IDRIS2_INC_MEMSTAT(n_tried_to_kill_immortals);
    return;
  }
  --(elem->header.refCounter);
  if (elem->header.refCounter != 0)
    return;
  IDRIS2_INC_MEMSTAT(n_freed);
    switch (elem->header.tag) {
    case BITS32_TAG:
    case BITS64_TAG:
    case INT32_TAG:
    case INT64_TAG:
      /* nothing to delete, added for sake of completeness */
      break;
    case INTEGER_TAG:
      mpz_clear(((Value_Integer *)elem)->i);
      break;

    case DOUBLE_TAG:
      /* nothing to delete, added for sake of completeness */
      break;

    case STRING_TAG:
      free(((Value_String *)elem)->str);
      break;

    case CLOSURE_TAG: {
      Value_Closure *cl = (Value_Closure *)elem;
      for (int i = 0; i < cl->filled; ++i)
        idris2_removeReference(cl->args[i]);
      break;
    }

    case CONSTRUCTOR_TAG: {
      Value_Constructor *constr = (Value_Constructor *)elem;
      for (int i = 0; i < constr->total; i++) {
        idris2_removeReference(constr->args[i]);
      }
      break;
    }
    case IOREF_TAG:
      idris2_removeReference(((Value_IORef *)elem)->v);
      break;

    case BUFFER_TAG: {
      Value_Buffer *b = (Value_Buffer *)elem;
      free(b->buffer);
      break;
    }

    case ARRAY_TAG: {
      Value_Array *a = (Value_Array *)elem;
      for (int i = 0; i < a->capacity; i++) {
        idris2_removeReference(a->arr[i]);
      }
      free(a->arr);
      break;
    }
    case POINTER_TAG:
      /* nothing to delete, added for sake of completeness */
      break;

    case GC_POINTER_TAG: {
      /* maybe here we need to invoke onCollectAny */
      Value_GCPointer *vPtr = (Value_GCPointer *)elem;
      Value *closure1 =
          idris2_apply_closure((Value *)vPtr->onCollectFct, (Value *)vPtr->p);
      idris2_apply_closure(closure1, NULL);
      idris2_removeReference((Value *)vPtr->p);
      break;
    }

    case MUTEX_TAG: {
      Value_Mutex *m = (Value_Mutex *)elem;
      pthread_mutex_destroy(m->mutex);
      free(m->mutex);
      break;
    }

    case CONDITION_TAG: {
      Value_Condition *c = (Value_Condition *)elem;
      pthread_cond_destroy(c->cond);
      free(c->cond);
      break;
    }

    default:
      break;
    }
    // finally, free element
    idris2_pool_dealloc(elem);
}

// /////////////////////////////////////////////////////////////////////////
// PRE-DEFINED VLAUES

#define IDRIS2_MK_PREDEFINED_INT_10(t, n)                                      \
  {IDRIS2_STOCKVAL(t), (n + 0)}, {IDRIS2_STOCKVAL(t), (n + 1)},                \
      {IDRIS2_STOCKVAL(t), (n + 2)}, {IDRIS2_STOCKVAL(t), (n + 3)},            \
      {IDRIS2_STOCKVAL(t), (n + 4)}, {IDRIS2_STOCKVAL(t), (n + 5)},            \
      {IDRIS2_STOCKVAL(t), (n + 6)}, {IDRIS2_STOCKVAL(t), (n + 7)},            \
      {IDRIS2_STOCKVAL(t), (n + 8)}, {                                         \
    IDRIS2_STOCKVAL(t), (n + 9)                                                \
  }
Value_Int64 const idris2_predefined_Int64[100] = {
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 0),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 10),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 20),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 30),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 40),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 50),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 60),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 70),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 80),
    IDRIS2_MK_PREDEFINED_INT_10(INT64_TAG, 90)};

Value_Bits64 const idris2_predefined_Bits64[100] = {
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 0),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 10),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 20),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 30),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 40),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 50),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 60),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 70),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 80),
    IDRIS2_MK_PREDEFINED_INT_10(BITS64_TAG, 90)};

Value_String const idris2_predefined_nullstring = {IDRIS2_STOCKVAL(STRING_TAG),
                                                   ""};

static bool idris2_predefined_integer_initialized = false;
Value_Integer idris2_predefined_Integer[100];

Value *idris2_getPredefinedInteger(int n) {
  IDRIS2_REFC_VERIFY(n >= 0 && n < 100,
                     "invalid range of predefined integers.");

  if (sizeof(uintptr_t) >= 8)
    return IDRIS2_MKFIXNUM(n);

  if (!idris2_predefined_integer_initialized) {
    idris2_predefined_integer_initialized = true;
    for (int i = 0; i < 100; ++i) {
      idris2_predefined_Integer[i].header.refCounter = IDRIS2_VP_REFCOUNTER_MAX;
      idris2_predefined_Integer[i].header.tag = INTEGER_TAG;
      idris2_predefined_Integer[i].header.reserved = 0;

      mpz_init(idris2_predefined_Integer[i].i);
      mpz_set_si(idris2_predefined_Integer[i].i, i);
    }
  }
  return (Value *)&idris2_predefined_Integer[n];
}

/* Quick RSS logger for leak hunting */

/* Quick RSS logger for leak hunting - Windows/MinGW */
#include <windows.h>
#include <psapi.h>
static int _rss_call_count = 0;
void idris2_log_rss(const char *label) {
  _rss_call_count++;
  PROCESS_MEMORY_COUNTERS pmc;
  if (GetProcessMemoryInfo(GetCurrentProcess(), &pmc, sizeof(pmc))) {
    fprintf(stderr, "[RSS] #%d %s: WorkingSet=%lluMB PeakWS=%lluMB\n",
            _rss_call_count, label,
            (unsigned long long)pmc.WorkingSetSize / (1024*1024),
            (unsigned long long)pmc.PeakWorkingSetSize / (1024*1024));
  }
}
