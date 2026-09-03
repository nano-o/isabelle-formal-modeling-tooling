#include "fee.h"

bool
mul_u64_checked(uint64_t a, uint64_t b, uint64_t *out)
{
    if (a != 0 && b > UINT64_MAX / a)
        return false;
    *out = a * b;
    return true;
}

fee_status
fee_ceil(int64_t amount, int32_t rate_bps, int64_t *fee)
{
    if (amount < 0)
        return FEE_NEGATIVE_AMOUNT;
    if (rate_bps < 0 || rate_bps > 10000)
        return FEE_BAD_RATE;
    uint64_t product;
    if (!mul_u64_checked((uint64_t)amount, (uint64_t)rate_bps, &product))
        return FEE_OVERFLOW;
    if (product > UINT64_MAX - 9999)
        return FEE_OVERFLOW;
    uint64_t scaled = (product + 9999) / 10000;
    if (scaled > (uint64_t)INT64_MAX)
        return FEE_OVERFLOW;
    *fee = (int64_t)scaled;
    return FEE_OK;
}
