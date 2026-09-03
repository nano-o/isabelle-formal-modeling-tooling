#ifndef FEE_H
#define FEE_H

#include <stdbool.h>
#include <stdint.h>

/* Outcome of a fee computation. When several failures apply, the one
   reported is the first the implementation checks; that order is part of
   the contract. */
typedef enum {
    FEE_OK = 0,
    FEE_NEGATIVE_AMOUNT = 1,
    FEE_BAD_RATE = 2,
    FEE_OVERFLOW = 3
} fee_status;

/* Stores a * b in *out and returns true when the product of two uint64_t
   values fits in 64 bits; otherwise returns false and leaves *out unchanged. */
bool mul_u64_checked(uint64_t a, uint64_t b, uint64_t *out);

/* Computes the fee on `amount` at `rate_bps` basis points, rounded up:
   ceil(amount * rate_bps / 10000). `amount` must be non-negative and
   `rate_bps` within [0, 10000]. On FEE_OK the fee is stored in *fee; on any
   other status *fee is left unchanged. */
fee_status fee_ceil(int64_t amount, int32_t rate_bps, int64_t *fee);

#endif
