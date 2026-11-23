#ifndef OT_ROOTLESS_COMPAT_H
#define OT_ROOTLESS_COMPAT_H

// OldTroll targets rootful jailbreaks (iOS 6-10). Keep paths unprefixed so
// binaries do not pull in the legacy libroot archive, which was built with
// fortify calls unavailable on iOS 6.
#define ROOT_PATH(path) path

#endif
