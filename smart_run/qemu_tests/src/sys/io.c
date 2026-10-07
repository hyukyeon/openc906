/* io.c — minimal runtime for rv64 Linux user-mode (qemu-riscv64)
 *
 * Provides: _start, printf (subset), puts, putchar
 * I/O via Linux ecall (write=64, exit_group=94)
 */

#include <stdarg.h>
#include <stddef.h>
#include <stdint.h>

/* --------------------------------------------------------------------------
 * Linux syscall primitives
 * -------------------------------------------------------------------------- */
static long _syscall3(long n, long a0, long a1, long a2) {
    register long ra0 asm("a0") = a0;
    register long ra1 asm("a1") = a1;
    register long ra2 asm("a2") = a2;
    register long ra7 asm("a7") = n;
    asm volatile("ecall" : "+r"(ra0) : "r"(ra1), "r"(ra2), "r"(ra7) : "memory");
    return ra0;
}

static long _syscall1(long n, long a0) {
    register long ra0 asm("a0") = a0;
    register long ra7 asm("a7") = n;
    asm volatile("ecall" : "+r"(ra0) : "r"(ra7) : "memory");
    return ra0;
}

void _exit(int code) {
    _syscall1(94, code);            /* exit_group */
    __builtin_unreachable();
}

static void _write_raw(const char *buf, size_t len) {
    _syscall3(64, 1, (long)buf, (long)len);   /* write(1, buf, len) */
}

/* --------------------------------------------------------------------------
 * Entry point
 * -------------------------------------------------------------------------- */
extern int main(void);

void __attribute__((naked)) _start(void) {
    asm volatile(
        "li  fp, 0\n"
        "li  ra, 0\n"
        "call main\n"
        "mv  a0, a0\n"
        "li  a7, 94\n"
        "ecall\n"
    );
}

/* --------------------------------------------------------------------------
 * Minimal printf — %d %i %u %x %X %f %s %c %%
 * -------------------------------------------------------------------------- */
static void _put_char(char c) { _write_raw(&c, 1); }

static void _put_str(const char *s) {
    if (!s) s = "(null)";
    size_t len = 0;
    while (s[len]) len++;
    _write_raw(s, len);
}

static void _put_uint(unsigned long v, int base, int upper,
                      int width, int zero_pad) {
    char buf[32];
    int  pos = 0;
    const char *digits = upper ? "0123456789ABCDEF" : "0123456789abcdef";

    if (v == 0) { buf[pos++] = '0'; }
    else { while (v) { buf[pos++] = digits[v % base]; v /= base; } }

    int pad = width - pos;
    char pc = zero_pad ? '0' : ' ';
    while (pad-- > 0) _put_char(pc);
    for (int i = pos - 1; i >= 0; i--) _put_char(buf[i]);
}

static void _put_int(long v, int width, int zero_pad) {
    if (v < 0) { _put_char('-'); v = -v; width--; }
    _put_uint((unsigned long)v, 10, 0, width, zero_pad);
}

int printf(const char *fmt, ...) {
    va_list ap;
    va_start(ap, fmt);

    while (*fmt) {
        if (*fmt != '%') { _put_char(*fmt++); continue; }
        fmt++;

        int zero_pad = 0, width = 0;
        if (*fmt == '0') { zero_pad = 1; fmt++; }
        while (*fmt >= '0' && *fmt <= '9') width = width * 10 + (*fmt++ - '0');

        int is_long = 0;
        if (*fmt == 'l') { is_long = 1; fmt++; }

        switch (*fmt++) {
            case 'd': case 'i': {
                long v = is_long ? va_arg(ap, long) : (long)va_arg(ap, int);
                _put_int(v, zero_pad ? width : 0, zero_pad);
                break;
            }
            case 'u': {
                unsigned long v = is_long ? va_arg(ap, unsigned long)
                                          : (unsigned long)va_arg(ap, unsigned int);
                _put_uint(v, 10, 0, zero_pad ? width : 0, zero_pad);
                break;
            }
            case 'x': {
                unsigned long v = is_long ? va_arg(ap, unsigned long)
                                          : (unsigned long)va_arg(ap, unsigned int);
                _put_uint(v, 16, 0, zero_pad ? width : 0, zero_pad);
                break;
            }
            case 's': {
                const char *s = va_arg(ap, const char *);
                _put_str(s ? s : "(null)");
                break;
            }
            case 'c':
                _put_char((char)va_arg(ap, int));
                break;
            case '%':
                _put_char('%');
                break;
            default:
                _put_char('?');
                break;
        }
    }

    va_end(ap);
    return 0;
}

int puts(const char *s) { _put_str(s); _put_char('\n'); return 0; }
int putchar(int c)       { _put_char((char)c); return c; }
