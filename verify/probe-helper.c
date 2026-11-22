#define _GNU_SOURCE
#include <cpuid.h>
#include <fcntl.h>
#include <setjmp.h>
#include <signal.h>
#include <ucontext.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/io.h>
#include <unistd.h>
#include <x86intrin.h>

enum { SAMPLES = 4001 };

static int ascending(const void *a, const void *b) {
    uint64_t x = *(const uint64_t *)a;
    uint64_t y = *(const uint64_t *)b;
    return (x > y) - (x < y);
}

static int fw_cfg(void) {
    if (ioperm(0x510, 12, 1) != 0) {
        perror("ioperm");
        return 1;
    }
    outw(0x0000, 0x510);
    char signature[5] = {0};
    for (int i = 0; i < 4; i++) {
        signature[i] = (char)inb(0x511);
    }
    uint32_t high = inl(0x514);
    uint32_t low = inl(0x518);
    printf("signature %s\n", signature);
    printf("dma %08x%08x\n", __builtin_bswap32(high), __builtin_bswap32(low));
    return 0;
}

static void cpuid_cycles(unsigned leaf, uint64_t *cycles) {
    unsigned a, b, c, d;
    for (int i = 0; i < SAMPLES; i++) {
        uint64_t start = __rdtsc();
        __cpuid(leaf, a, b, c, d);
        cycles[i] = __rdtsc() - start;
    }
    qsort(cycles, SAMPLES, sizeof cycles[0], ascending);
}

static int cpuid_latency(void) {
    static uint64_t cycles[SAMPLES];
    static uint64_t leaf1[SAMPLES];
    static uint64_t pairs[SAMPLES];
    unsigned a, b, c, d;
    cpuid_cycles(0, cycles);
    cpuid_cycles(1, leaf1);
    for (int i = 0; i < SAMPLES; i++) {
        uint64_t start = __rdtsc();
        pairs[i] = __rdtsc() - start;
    }
    qsort(pairs, SAMPLES, sizeof pairs[0], ascending);
    __cpuid(0, a, b, c, d);
    char vendor[13];
    memcpy(vendor, &b, 4);
    memcpy(vendor + 4, &d, 4);
    memcpy(vendor + 8, &c, 4);
    vendor[12] = 0;
    printf("median %llu\n", (unsigned long long)cycles[SAMPLES / 2]);
    printf("leaf1 %llu\n", (unsigned long long)leaf1[SAMPLES / 2]);
    printf("min %llu\n", (unsigned long long)leaf1[0]);
    printf("pair %llu\n", (unsigned long long)pairs[SAMPLES / 2]);
    printf("leaf0 0x%x %s\n", a, vendor);
    unsigned brand[13] = {0};
    for (unsigned i = 0; i < 3; i++) {
        __cpuid(0x80000002 + i, brand[4 * i], brand[4 * i + 1], brand[4 * i + 2], brand[4 * i + 3]);
    }
    printf("brand %s\n", (const char *)brand);
    return 0;
}

enum { NAME_STRING_MSR = 0xc0010030, NAME_STRING_MSRS = 6 };

static int name_msr(void) {
    int fd = open("/dev/cpu/0/msr", O_RDWR);
    if (fd < 0) {
        perror("/dev/cpu/0/msr");
        return 1;
    }
    uint64_t name[NAME_STRING_MSRS];
    int programmable = 1;
    for (int i = 0; i < NAME_STRING_MSRS && programmable; i++) {
        programmable = pread(fd, &name[i], sizeof name[i], NAME_STRING_MSR + i) == sizeof name[i];
    }
    if (programmable) {
        programmable = pwrite(fd, &name[0], sizeof name[0], NAME_STRING_MSR) == sizeof name[0];
    }
    close(fd);
    printf("programmable %d\n", programmable);
    return 0;
}

enum { PM_TIMER_MASK = 0xffffff, HIDDEN_LOOPS = 20000 };

static int pm_timer_port(void) {
    FILE *fadt = fopen("/sys/firmware/acpi/tables/FACP", "rb");
    if (fadt == NULL) {
        perror("FACP");
        return -1;
    }
    uint32_t port = 0;
    int found = fseek(fadt, 76, SEEK_SET) == 0 && fread(&port, sizeof port, 1, fadt) == 1;
    fclose(fadt);
    if (!found || port == 0 || port > 0xfffc) {
        fprintf(stderr, "the FADT names no PM timer port\n");
        return -1;
    }
    if (ioperm(port, 4, 1) != 0) {
        perror("ioperm");
        return -1;
    }
    return (int)port;
}

static uint32_t pm_ticks(int port, uint32_t from) {
    return (inl((unsigned short)port) - from) & PM_TIMER_MASK;
}

static int tsc_hidden(void) {
    int port = pm_timer_port();
    if (port < 0) {
        return 1;
    }
    unsigned a, b, c, d;
    uint32_t start = inl((unsigned short)port);
    uint64_t tsc = __rdtsc();
    uint32_t span;
    do {
        span = pm_ticks(port, start);
    } while (span < 357954);
    double rate = (double)(__rdtsc() - tsc) / span;
    start = inl((unsigned short)port);
    tsc = __rdtsc();
    for (int i = 0; i < HIDDEN_LOOPS; i++) {
        __cpuid(1, a, b, c, d);
    }
    uint64_t seen = __rdtsc() - tsc;
    span = pm_ticks(port, start);
    double hidden = 1.0 - (double)seen / (span * rate);
    printf("rate %.1f\n", rate);
    printf("seen %llu\n", (unsigned long long)seen);
    printf("elapsed %.0f\n", span * rate);
    printf("hidden %d\n", (int)(hidden * 1000.0));
    return 0;
}

static sigjmp_buf instruction_return;
static volatile sig_atomic_t instruction_signal;
static volatile uintptr_t instruction_rip;

static void on_instruction_signal(int sig, siginfo_t *info, void *context) {
    (void)info;
    instruction_signal = sig;
    instruction_rip = (uintptr_t)((ucontext_t *)context)->uc_mcontext.gregs[REG_RIP];
    siglongjmp(instruction_return, 1);
}

extern char vmload_at[], vmload_end[], vmcall_at[], vmcall_end[];
extern char vmmcall_at[], vmmcall_end[], icebp_at[], icebp_end[];
extern char cpuidstep_at[], cpuidstep_end[];

__attribute__((noinline)) static void run_vmload(void) {
    __asm__ volatile("vmload_at: .byte 0x0f, 0x01, 0xda\nvmload_end:" ::: "memory");
}

__attribute__((noinline)) static void run_vmcall(void) {
    __asm__ volatile("vmcall_at: .byte 0x0f, 0x01, 0xc1\nvmcall_end:" ::: "rax", "memory");
}

__attribute__((noinline)) static void run_vmmcall(void) {
    __asm__ volatile("vmmcall_at: .byte 0x0f, 0x01, 0xd9\nvmmcall_end:" ::: "rax", "memory");
}

__attribute__((noinline)) static void run_icebp(void) {
    __asm__ volatile("icebp_at: .byte 0xf1\nicebp_end:" ::: "memory");
}

__attribute__((noinline)) static void run_cpuidstep(void) {
    __asm__ volatile("xor %%eax, %%eax\n"
                     "xor %%ecx, %%ecx\n"
                     "pushfq\n"
                     "orq $0x100, (%%rsp)\n"
                     "popfq\n"
                     "cpuidstep_at: cpuid\n"
                     "cpuidstep_end: nop\n" ::
                         : "rax", "rbx", "rcx", "rdx", "memory", "cc");
}

static const char *signal_word(int sig) {
    switch (sig) {
    case 0:
        return "none";
    case SIGILL:
        return "ill";
    case SIGSEGV:
        return "segv";
    case SIGTRAP:
        return "trap";
    case SIGBUS:
        return "bus";
    default:
        return "other";
    }
}

static void try_instruction(const char *name, void (*run)(void), const char *at, const char *end) {
    instruction_signal = 0;
    instruction_rip = 0;
    if (sigsetjmp(instruction_return, 1) == 0) {
        run();
    }
    const char *where = "none";
    if (instruction_signal != 0) {
        where = instruction_rip == (uintptr_t)end ? "after" : instruction_rip == (uintptr_t)at ? "at" : "elsewhere";
    }
    printf("%s %s %s\n", name, signal_word(instruction_signal), where);
}

static int instructions(void) {
    struct sigaction action = {0};
    action.sa_sigaction = on_instruction_signal;
    action.sa_flags = SA_SIGINFO | SA_NODEFER;
    sigemptyset(&action.sa_mask);
    int signals[] = {SIGILL, SIGSEGV, SIGTRAP, SIGBUS};
    for (unsigned i = 0; i < sizeof signals / sizeof signals[0]; i++) {
        if (sigaction(signals[i], &action, NULL) != 0) {
            perror("sigaction");
            return 1;
        }
    }
    try_instruction("vmload", run_vmload, vmload_at, vmload_end);
    try_instruction("vmcall", run_vmcall, vmcall_at, vmcall_end);
    try_instruction("vmmcall", run_vmmcall, vmmcall_at, vmmcall_end);
    try_instruction("icebp", run_icebp, icebp_at, icebp_end);
    try_instruction("cpuidstep", run_cpuidstep, cpuidstep_at, cpuidstep_end);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 2 && strcmp(argv[1], "fw-cfg") == 0) {
        return fw_cfg();
    }
    if (argc == 2 && strcmp(argv[1], "cpuid-latency") == 0) {
        return cpuid_latency();
    }
    if (argc == 2 && strcmp(argv[1], "instructions") == 0) {
        return instructions();
    }
    if (argc == 2 && strcmp(argv[1], "tsc-hidden") == 0) {
        return tsc_hidden();
    }
    if (argc == 2 && strcmp(argv[1], "name-msr") == 0) {
        return name_msr();
    }
    fprintf(stderr, "usage: probe-helper fw-cfg|cpuid-latency|tsc-hidden|instructions|name-msr\n");
    return 2;
}
