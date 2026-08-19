#include "CLibarchiveShim.h"
#include <archive.h>
#include <archive_entry.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static LAResult result(struct archive *a, int status, const char *fallback) {
    LAResult r = { .status = status, .system_errno = a ? archive_errno(a) : errno };
    const char *message = a ? archive_error_string(a) : NULL;
    snprintf(r.message, sizeof(r.message), "%s", message ? message : fallback);
    return r;
}

static int configure_reader(struct archive *a, LAProfile p) {
    int s = ARCHIVE_OK;
    switch (p) {
    case LA_TAR: case LA_TAR_GZIP: case LA_TAR_BZIP2: case LA_TAR_XZ: case LA_TAR_ZSTD:
        s = archive_read_support_format_tar(a); break;
    case LA_CPIO: s = archive_read_support_format_cpio(a); break;
    case LA_ISO: s = archive_read_support_format_iso9660(a); break;
    case LA_GZIP: case LA_BZIP2: case LA_XZ: s = archive_read_support_format_raw(a); break;
    }
    if (s < ARCHIVE_WARN) return s;
    switch (p) {
    case LA_TAR_GZIP: case LA_GZIP: return archive_read_support_filter_gzip(a);
    case LA_TAR_BZIP2: case LA_BZIP2: return archive_read_support_filter_bzip2(a);
    case LA_TAR_XZ: case LA_XZ: return archive_read_support_filter_xz(a);
    case LA_TAR_ZSTD: return archive_read_support_filter_zstd(a);
    default: return archive_read_support_filter_none(a);
    }
}

static LAEntryKind kind(struct archive_entry *e) {
    if (archive_entry_hardlink(e)) return LA_ENTRY_HARDLINK;
    switch (archive_entry_filetype(e)) {
    case AE_IFREG: return LA_ENTRY_REGULAR; case AE_IFDIR: return LA_ENTRY_DIRECTORY;
    case AE_IFLNK: return LA_ENTRY_SYMLINK; case AE_IFBLK: return LA_ENTRY_BLOCK;
    case AE_IFCHR: return LA_ENTRY_CHARACTER; case AE_IFIFO: return LA_ENTRY_FIFO;
    case AE_IFSOCK: return LA_ENTRY_SOCKET; default: return LA_ENTRY_UNKNOWN;
    }
}

static LAEntryInfo info(struct archive_entry *e) {
    const char *link = archive_entry_hardlink(e);
    if (!link) link = archive_entry_symlink(e);
    return (LAEntryInfo){ archive_entry_pathname(e), link, kind(e),
        archive_entry_size_is_set(e) ? archive_entry_size(e) : -1,
        archive_entry_mtime_is_set(e) ? archive_entry_mtime(e) : INT64_MIN,
        archive_entry_mtime_is_set(e) ? archive_entry_mtime_nsec(e) : 0,
        archive_entry_mode(e), archive_entry_uid_is_set(e) ? archive_entry_uid(e) : -1,
        archive_entry_gid_is_set(e) ? archive_entry_gid(e) : -1 };
}

const char *la_runtime_version(void) { return archive_version_string(); }

int la_profile_available(LAProfile p, int writing) {
    if (p == LA_TAR_ZSTD) return archive_libzstd_version() != NULL;
    if (p == LA_TAR_XZ || p == LA_XZ) return archive_liblzma_version() != NULL;
    if (p == LA_TAR_BZIP2 || p == LA_BZIP2) return archive_bzlib_version() != NULL;
    if (p == LA_TAR_GZIP || p == LA_GZIP) return archive_zlib_version() != NULL;
    if (p == LA_ISO && writing) return 0;
    return 1;
}

static struct archive *open_reader(const char *path, LAProfile p, LAResult *out) {
    struct archive *a = archive_read_new();
    if (!a) { *out = result(NULL, ARCHIVE_FATAL, "archive_read_new failed"); return NULL; }
    int s = configure_reader(a, p);
    if (s < ARCHIVE_WARN || (s = archive_read_open_filename(a, path, 64 * 1024)) < ARCHIVE_WARN) {
        *out = result(a, s, "Unable to open archive"); archive_read_free(a); return NULL;
    }
    return a;
}

LAResult la_list(const char *path, LAProfile p, LAEntryCallback callback, void *context) {
    LAResult r = { .status = ARCHIVE_OK }; struct archive *a = open_reader(path, p, &r);
    if (!a) return r;
    struct archive_entry *e; int s;
    while ((s = archive_read_next_header(a, &e)) != ARCHIVE_EOF) {
        if (s < ARCHIVE_WARN) { r = result(a, s, "Header read failed"); break; }
        LAEntryInfo i = info(e);
        if (!i.path || callback(context, &i)) { r = result(a, ARCHIVE_FATAL, "Cancelled"); r.system_errno = ECANCELED; break; }
        s = archive_read_data_skip(a);
        if (s < ARCHIVE_WARN) { r = result(a, s, "Entry skip failed"); break; }
    }
    int close_status = archive_read_close(a); if (r.status == ARCHIVE_OK && close_status < ARCHIVE_WARN) r = result(a, close_status, "Close failed");
    archive_read_free(a); return r;
}

static const char *planned_path(const LAExtractionPlan *plans, size_t n, const char *path) {
    for (size_t i = 0; i < n; i++) if (!strcmp(plans[i].archive_path, path)) return plans[i].partial_path;
    return NULL;
}

LAResult la_extract(const char *path, LAProfile p, const LAExtractionPlan *plans, size_t n, LAProgressCallback cb, void *ctx) {
    LAResult r = { .status = ARCHIVE_OK }; struct archive *a = open_reader(path, p, &r); if (!a) return r;
    struct archive_entry *e; int s; char buffer[64 * 1024]; uint64_t total = 0;
    while ((s = archive_read_next_header(a, &e)) != ARCHIVE_EOF) {
        if (s < ARCHIVE_WARN) { r = result(a, s, "Header read failed"); break; }
        const char *entry_path = archive_entry_pathname(e); const char *out = entry_path ? planned_path(plans, n, entry_path) : NULL;
        if (!out || kind(e) != LA_ENTRY_REGULAR) { archive_read_data_skip(a); continue; }
        int fd = open(out, O_WRONLY | O_CREAT | O_EXCL, 0600);
        if (fd < 0) { r = result(NULL, ARCHIVE_FAILED, "Unable to create partial file"); break; }
        int failed = 0; la_ssize_t count;
        while ((count = archive_read_data(a, buffer, sizeof(buffer))) > 0) {
            ssize_t offset = 0; while (offset < count) { ssize_t wrote = write(fd, buffer + offset, (size_t)(count - offset)); if (wrote <= 0) { failed = 1; break; } offset += wrote; }
            total += (uint64_t)count; if (failed || (cb && cb(ctx, total, entry_path))) { errno = failed ? errno : ECANCELED; failed = 1; break; }
        }
        if (count < 0) failed = 1;
        if (!failed && fsync(fd)) failed = 1;
        if (close(fd) && !failed) failed = 1;
        if (failed) { unlink(out); r = result(a, errno == ECANCELED ? ARCHIVE_FATAL : ARCHIVE_FAILED, "Streaming extraction failed"); r.system_errno = errno; break; }
    }
    archive_read_close(a); archive_read_free(a); return r;
}

static int configure_writer(struct archive *a, LAProfile p) {
    int s;
    if (p == LA_CPIO) s = archive_write_set_format_cpio_newc(a);
    else if (p == LA_GZIP || p == LA_BZIP2 || p == LA_XZ) s = archive_write_set_format_raw(a);
    else s = archive_write_set_format_pax_restricted(a);
    if (s < ARCHIVE_WARN) return s;
    switch (p) { case LA_TAR_GZIP: case LA_GZIP: return archive_write_add_filter_gzip(a);
    case LA_TAR_BZIP2: case LA_BZIP2: return archive_write_add_filter_bzip2(a);
    case LA_TAR_XZ: case LA_XZ: return archive_write_add_filter_xz(a);
    case LA_TAR_ZSTD: return archive_write_add_filter_zstd(a); default: return ARCHIVE_OK; }
}

LAResult la_create(const char *path, LAProfile p, const LACreationSource *sources, size_t n,
                   int compression_level, int threads, LAProgressCallback cb, void *ctx) {
    struct archive *a = archive_write_new(); if (!a) return result(NULL, ARCHIVE_FATAL, "archive_write_new failed");
    int s = configure_writer(a, p);
    char option[32];
    if (s >= ARCHIVE_WARN && compression_level >= 0) {
        snprintf(option, sizeof(option), "%d", compression_level);
        s = archive_write_set_filter_option(a, NULL, "compression-level", option);
    }
    if (s >= ARCHIVE_WARN && threads >= 0 && (p == LA_TAR_XZ || p == LA_XZ)) {
        snprintf(option, sizeof(option), "%d", threads);
        s = archive_write_set_filter_option(a, "xz", "threads", option);
    }
    if (s < ARCHIVE_WARN || (s = archive_write_open_filename(a, path)) < ARCHIVE_WARN) { LAResult r=result(a,s,"Writer open failed"); archive_write_free(a); return r; }
    LAResult r = { .status = ARCHIVE_OK }; char buffer[64 * 1024]; uint64_t total = 0;
    for (size_t i=0; i<n; i++) {
        struct stat st; if (lstat(sources[i].source_path, &st)) { r=result(NULL,ARCHIVE_FAILED,"Source stat failed"); break; }
        struct archive_entry *e=archive_entry_new(); archive_entry_set_pathname(e,sources[i].archive_path);
        archive_entry_copy_stat(e,&st);
        char linkbuf[4096]; if (S_ISLNK(st.st_mode)) { ssize_t len=readlink(sources[i].source_path,linkbuf,sizeof(linkbuf)-1); if(len<0){archive_entry_free(e);r=result(NULL,ARCHIVE_FAILED,"readlink failed");break;} linkbuf[len]=0; archive_entry_set_symlink_utf8(e,linkbuf); archive_entry_set_size(e,0); }
        s=archive_write_header(a,e); if(s<ARCHIVE_WARN){archive_entry_free(e);r=result(a,s,"Header write failed");break;}
        if(S_ISREG(st.st_mode)){ int fd=open(sources[i].source_path,O_RDONLY); if(fd<0){archive_entry_free(e);r=result(NULL,ARCHIVE_FAILED,"Source open failed");break;} ssize_t count; while((count=read(fd,buffer,sizeof(buffer)))>0){ la_ssize_t wrote=archive_write_data(a,buffer,(size_t)count); if(wrote!=count){r=result(a,ARCHIVE_FAILED,"Data write failed");break;} total+=(uint64_t)count; if(cb&&cb(ctx,total,sources[i].archive_path)){r=result(a,ARCHIVE_FATAL,"Cancelled");r.system_errno=ECANCELED;break;} } close(fd); }
        archive_entry_free(e); if(r.status<ARCHIVE_WARN) break;
    }
    archive_write_close(a); archive_write_free(a); return r;
}

LAResult la_test(const char *path, LAProfile p, LAProgressCallback cb, void *ctx) {
    LAResult r={.status=ARCHIVE_OK}; struct archive *a=open_reader(path,p,&r); if(!a)return r; struct archive_entry *e; int s; char b[64*1024]; uint64_t total=0;
    while((s=archive_read_next_header(a,&e))!=ARCHIVE_EOF){if(s<ARCHIVE_WARN){r=result(a,s,"Header read failed");break;} la_ssize_t n; while((n=archive_read_data(a,b,sizeof(b)))>0){total+=(uint64_t)n;if(cb&&cb(ctx,total,archive_entry_pathname(e))){r=result(a,ARCHIVE_FATAL,"Cancelled");r.system_errno=ECANCELED;break;}} if(n<0){r=result(a,ARCHIVE_FAILED,"Data validation failed");break;} if(r.status<ARCHIVE_WARN)break;}
    archive_read_close(a); archive_read_free(a); return r;
}
