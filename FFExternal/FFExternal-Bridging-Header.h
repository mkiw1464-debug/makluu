#ifndef FFExternal_Bridging_Header_h
#define FFExternal_Bridging_Header_h

#import "exploit/bad_query.h"
#import "exploit/mcm_bridge.h"
#import "exploit/wallpaper_zip.h"
#import "kexploit/kexploit_opa334.h"
#import "kexploit/krw.h"
#import "kexploit/kutils.h"
#import "kexploit/offsets.h"
#import "kexploit/vnode.h"
#import "kexploit/sandbox_escape.h"
#import "kexploit/machine_info.h"
#import "kexploit/xpaci.h"


#include <sys/types.h>
#include <sys/ptrace.h>

// Wrapper so Swift can call ptrace without variadic issues
static inline int ff_deny_attach(void) {
    return ptrace(PT_DENY_ATTACH, 0, (caddr_t)0, 0);
}

#endif /* FFExternal_Bridging_Header_h */
