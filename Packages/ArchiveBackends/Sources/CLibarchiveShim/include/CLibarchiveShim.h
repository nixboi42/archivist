#ifndef C_LIBARCHIVE_SHIM_H
#define C_LIBARCHIVE_SHIM_H

#include <stdint.h>
#include <stddef.h>

typedef enum { LA_TAR, LA_TAR_GZIP, LA_TAR_BZIP2, LA_TAR_XZ, LA_TAR_ZSTD,
               LA_CPIO, LA_GZIP, LA_BZIP2, LA_XZ, LA_ISO } LAProfile;

typedef enum { LA_ENTRY_REGULAR, LA_ENTRY_DIRECTORY, LA_ENTRY_SYMLINK,
               LA_ENTRY_HARDLINK, LA_ENTRY_BLOCK, LA_ENTRY_CHARACTER,
               LA_ENTRY_FIFO, LA_ENTRY_SOCKET, LA_ENTRY_UNKNOWN } LAEntryKind;

typedef struct {
    const char *path;
    const char *link_target;
    LAEntryKind kind;
    int64_t size;
    int64_t mtime_seconds;
    long mtime_nanoseconds;
    uint32_t mode;
    int64_t uid;
    int64_t gid;
} LAEntryInfo;

typedef struct { int status; int system_errno; char message[512]; } LAResult;
typedef int (*LAEntryCallback)(void *context, const LAEntryInfo *entry);
typedef int (*LAProgressCallback)(void *context, uint64_t bytes, const char *path);

typedef struct { const char *archive_path; const char *partial_path; } LAExtractionPlan;
typedef struct { const char *source_path; const char *archive_path; } LACreationSource;

const char *la_runtime_version(void);
int la_profile_available(LAProfile profile, int writing);
LAResult la_list(const char *archive_path, LAProfile profile, LAEntryCallback callback, void *context);
LAResult la_extract(const char *archive_path, LAProfile profile, const LAExtractionPlan *plans,
                    size_t plan_count, LAProgressCallback callback, void *context);
LAResult la_create(const char *archive_path, LAProfile profile, const LACreationSource *sources,
                   size_t source_count, int compression_level, int threads,
                   LAProgressCallback callback, void *context);
LAResult la_test(const char *archive_path, LAProfile profile, LAProgressCallback callback, void *context);

#endif
