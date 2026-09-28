#define COMMON_DIGEST_FOR_OPENSSL 1
#include "StorageTraversal.h"
#include <CommonCrypto/CommonDigest.h>
#include <fts.h>
#include <sys/stat.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>

#pragma clang diagnostic ignored "-Wdeprecated-declarations"

typedef struct {
    CC_SHA256_CTX hash;
    int64_t bytes;
    uint64_t files;
    double latest_modified;
    int complete;
} Frame;
typedef struct { uint64_t device, inode; int used; } Link;
typedef struct { Link *entries; size_t capacity, count; } Links;

static uint64_t link_hash(uint64_t device, uint64_t inode) {
    uint64_t x = inode ^ (device * 0x9e3779b97f4a7c15ULL);
    x ^= x >> 30; x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 27; x *= 0x94d049bb133111ebULL;
    return x ^ (x >> 31);
}
static int insert_link(Links *links, uint64_t device, uint64_t inode) {
    if (!links->capacity || links->count * 2 >= links->capacity) {
        size_t capacity = links->capacity ? links->capacity * 2 : 128;
        Link *entries = calloc(capacity, sizeof(Link));
        if (!entries) return 1; // Counting twice is preferable to dropping data on allocation failure.
        for (size_t i = 0; i < links->capacity; i++) if (links->entries[i].used) {
            Link old = links->entries[i];
            size_t j = link_hash(old.device, old.inode) & (capacity - 1);
            while (entries[j].used) j = (j + 1) & (capacity - 1);
            entries[j] = old;
        }
        free(links->entries);
        links->entries = entries; links->capacity = capacity;
    }
    size_t i = link_hash(device, inode) & (links->capacity - 1);
    while (links->entries[i].used) {
        if (links->entries[i].device == device && links->entries[i].inode == inode) return 0;
        i = (i + 1) & (links->capacity - 1);
    }
    links->entries[i] = (Link){device, inode, 1};
    links->count++;
    return 1;
}
static int compare_entries(const FTSENT **a, const FTSENT **b) {
    return strcmp((*a)->fts_name, (*b)->fts_name);
}
static void seed_hash(CC_SHA256_CTX *hash, const FTSENT *entry) {
    const struct stat *s = entry->fts_statp;
    uint64_t values[] = {
        (uint64_t)s->st_dev, (uint64_t)s->st_ino, (uint64_t)s->st_mode,
        (uint64_t)s->st_size, (uint64_t)s->st_mtimespec.tv_sec,
        (uint64_t)s->st_mtimespec.tv_nsec, (uint64_t)s->st_ctimespec.tv_sec,
        (uint64_t)s->st_ctimespec.tv_nsec, (uint64_t)s->st_nlink,
        (uint64_t)entry->fts_namelen
    };
    CC_SHA256_Init(hash);
    CC_SHA256_Update(hash, values, (CC_LONG)sizeof(values));
    CC_SHA256_Update(hash, entry->fts_name, (CC_LONG)entry->fts_namelen);
}
static SMEntry make_entry(FTSENT *node, int kind, uint64_t count, int64_t total) {
    SMEntry out = {0};
    out.path = node->fts_path; out.kind = kind; out.depth = node->fts_level;
    out.file_count = count; out.total_bytes = total; out.complete = 1;
    if (node->fts_statp && node->fts_info != FTS_NS && node->fts_info != FTS_ERR) {
        struct stat *s = node->fts_statp;
        out.device = (uint64_t)s->st_dev; out.inode = (uint64_t)s->st_ino;
        out.logical_bytes = s->st_size; out.links = s->st_nlink;
        out.modified = (double)s->st_mtimespec.tv_sec + (double)s->st_mtimespec.tv_nsec / 1e9;
        out.created = (double)s->st_birthtimespec.tv_sec + (double)s->st_birthtimespec.tv_nsec / 1e9;
        out.latest_modified = out.modified;
    }
    return out;
}
static void append_to_parent(FTSENT *node, int64_t bytes, uint64_t files, double modified, const unsigned char *digest, int complete) {
    Frame *parent = node->fts_parent ? node->fts_parent->fts_pointer : NULL;
    if (!parent) return;
    parent->bytes += bytes;
    parent->files += files;
    if (modified > parent->latest_modified) parent->latest_modified = modified;
    parent->complete &= complete;
    if (digest) CC_SHA256_Update(&parent->hash, digest, 32);
}

int sm_walk(const char *path, int64_t minimum_bytes, int skip_git, SMCallback callback, void *context) {
    char *paths[] = {strdup(path), NULL};
    if (!paths[0]) return 2;
    FTS *tree = fts_open(paths, FTS_PHYSICAL | FTS_XDEV | FTS_NOCHDIR, compare_entries);
    if (!tree) { free(paths[0]); return 2; }
    FTSENT *node;
    uint64_t count = 0;
    int64_t total = 0;
    uint64_t device = 0;
    int status = 0;
    Links links = {0};
    while (1) {
        errno = 0;
        node = fts_read(tree);
        if (!node) {
            if (errno != 0) status = 2;
            break;
        }
        SMEntry out = make_entry(node, SM_PROGRESS, count, total);
        if (node->fts_level == 0) device = out.device;
        if (node->fts_info == FTS_D) {
            if (node->fts_level == 0) device = out.device;
            int skip = (skip_git && node->fts_level > 0 && strcasecmp(node->fts_name, ".git") == 0)
                || out.device != device || (node->fts_statp->st_flags & SF_DATALESS);
            if (skip) {
                fts_set(tree, node, FTS_SKIP);
                append_to_parent(node, 0, 0, out.modified, NULL, 0);
                out.kind = SM_ISSUE; out.complete = 0;
                if (callback(&out, context)) { status = 1; break; }
                continue;
            }
            Frame *frame = calloc(1, sizeof(Frame));
            if (!frame) { status = 2; break; }
            frame->complete = 1; frame->latest_modified = out.modified;
            seed_hash(&frame->hash, node);
            node->fts_pointer = frame;
            out.kind = SM_ENTER;
            if (callback(&out, context)) { status = 1; break; }
        } else if (node->fts_info == FTS_DP) {
            Frame *frame = node->fts_pointer;
            if (!frame) continue;
            out.kind = SM_LEAVE; out.bytes = frame->bytes; out.complete = frame->complete;
            out.subtree_file_count = frame->files;
            out.latest_modified = frame->latest_modified;
            CC_SHA256_Final(out.digest, &frame->hash);
            append_to_parent(node, frame->bytes, frame->files, frame->latest_modified, out.digest, frame->complete);
            free(frame); node->fts_pointer = NULL;
            if (callback(&out, context)) { status = 1; break; }
        } else if (node->fts_info == FTS_F || node->fts_info == FTS_SL || node->fts_info == FTS_SLNONE || node->fts_info == FTS_DEFAULT) {
            if (skip_git && node->fts_level > 0 && strcasecmp(node->fts_name, ".git") == 0) {
                out.kind = SM_ISSUE; out.complete = 0;
                append_to_parent(node, 0, 0, out.modified, NULL, 0);
                if (callback(&out, context)) { status = 1; break; }
                continue;
            }
            if ((node->fts_statp->st_flags & SF_DATALESS) || out.device != device) {
                out.kind = SM_ISSUE; out.complete = 0;
                append_to_parent(node, 0, 0, out.modified, NULL, 0);
                if (callback(&out, context)) { status = 1; break; }
                continue;
            }
            CC_SHA256_CTX hash;
            seed_hash(&hash, node);
            CC_SHA256_Final(out.digest, &hash);
            int is_file = node->fts_info == FTS_F;
            int unique = !is_file || out.links <= 1 || insert_link(&links, out.device, out.inode);
            int64_t allocated = is_file && unique ? (int64_t)node->fts_statp->st_blocks * 512 : 0;
            out.subtree_file_count = is_file && unique ? 1 : 0;
            append_to_parent(node, allocated, out.subtree_file_count, out.modified, out.digest, 1);
            if (is_file && unique) { count++; total += allocated; }
            out.bytes = allocated; out.file_count = count; out.total_bytes = total;
            if (is_file && unique && out.links <= 1 && (allocated >= minimum_bytes || node->fts_level == 0)) {
                out.kind = SM_FILE;
                if (callback(&out, context)) { status = 1; break; }
            } else if (count % 512 == 0) {
                if (callback(&out, context)) { status = 1; break; }
            }
        } else if (node->fts_info == FTS_DNR || node->fts_info == FTS_ERR || node->fts_info == FTS_NS || node->fts_info == FTS_DC) {
            out.kind = SM_ISSUE; out.complete = 0;
            append_to_parent(node, 0, 0, out.modified, NULL, 0);
            if (node->fts_level == 0) { status = 2; break; }
            if (node->fts_pointer) { free(node->fts_pointer); node->fts_pointer = NULL; }
            if (callback(&out, context)) { status = 1; break; }
        }
    }
    if (node) {
        // fts_close frees FTS nodes, not the application-owned state on their ancestors.
        for (FTSENT *p = node; p && p->fts_level >= 0; p = p->fts_parent) {
            if (p->fts_pointer) { free(p->fts_pointer); p->fts_pointer = NULL; }
        }
    }
    fts_close(tree);
    free(paths[0]); free(links.entries);
    return status;
}
