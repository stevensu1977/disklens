#ifndef STORAGE_TRAVERSAL_H
#define STORAGE_TRAVERSAL_H
#include <stdint.h>

enum { SM_ENTER = 1, SM_LEAVE = 2, SM_FILE = 3, SM_ISSUE = 4, SM_PROGRESS = 5 };
typedef struct {
    const char *path;
    int kind;
    int depth;
    int complete;
    int64_t bytes;
    int64_t logical_bytes;
    uint64_t device;
    uint64_t inode;
    double modified;
    double created;
    double latest_modified;
    uint64_t file_count;
    uint64_t subtree_file_count;
    int64_t total_bytes;
    uint32_t links;
    unsigned char digest[32];
} SMEntry;
typedef int (*SMCallback)(const SMEntry *, void *);

// 0 success, 1 cancelled, 2 unreadable root. Metadata only; never follows symlinks.
int sm_walk(const char *path, int64_t minimum_bytes, int skip_git, SMCallback callback, void *context);
#endif
