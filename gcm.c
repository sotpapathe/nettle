/* gcm.h
 *
 * Galois counter mode, specified by NIST,
 * http://csrc.nist.gov/publications/nistpubs/800-38D/SP-800-38D.pdf
 *
 */

/* NOTE: Tentative interface, subject to change. No effort will be
   made to avoid incompatible changes. */

/* nettle, low-level cryptographics library
 *
 * Copyright (C) 2011 Niels Möller
 * Copyright (C) 2011 Katholieke Universiteit Leuven
 * 
 * Contributed by Nikos Mavrogiannopoulos
 *
 * The nettle library is free software; you can redistribute it and/or modify
 * it under the terms of the GNU Lesser General Public License as published by
 * the Free Software Foundation; either version 2.1 of the License, or (at your
 * option) any later version.
 * 
 * The nettle library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 * 
 * You should have received a copy of the GNU Lesser General Public License
 * along with the nettle library; see the file COPYING.LIB.  If not, write to
 * the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston,
 * MA 02111-1307, USA.
 */

#if HAVE_CONFIG_H
# include "config.h"
#endif

#include <assert.h>
#include <stdlib.h>
#include <string.h>

#include "gcm.h"

#include "memxor.h"
#include "nettle-internal.h"
#include "macros.h"

#define GHASH_POLYNOMIAL 0xE1

/* Multiplication by 010...0; a big-endian shift right. If the bit
   shifted out is one, the defining polynomial is added to cancel it
   out. The argument must be properly aligned for word accesses. */
static void
gcm_gf_shift (uint8_t *x)
{
  unsigned long *w = (unsigned long *) x;
  long mask;
  /* Shift uses big-endian representation. */
#if WORDS_BIGENDIAN
# if SIZEOF_LONG == 4
  mask = - (w[3] & 1);
  w[3] = (w[3] >> 1) | ((w[2] & 1) << 31);
  w[2] = (w[2] >> 1) | ((w[1] & 1) << 31);
  w[1] = (w[1] >> 1) | ((w[0] & 1) << 31);
  w[0] = (w[0] >> 1) ^ (mask & (GHASH_POLYNOMIAL << 24)); 
# elif SIZEOF_LONG == 8
  mask = - (w[1] & 1);
  w[1] = (w[1] >> 1) | ((w[0] & 1) << 63);
  w[0] = (w[0] >> 1) ^ (mask & (GHASH_POLYNOMIAL << 56));
# else
#  error Unsupported word size. */
#endif
#else /* ! WORDS_BIGENDIAN */
# if SIZEOF_LONG == 4
#define RSHIFT_WORD(x) \
  ((((x) & 0xfefefefeUL) >> 1) \
   | (((x) & 0x00010101) << 15))
  mask = - ((w[3] >> 24) & 1);
  w[3] = RSHIFT_WORD(w[3]) | ((w[2] >> 17) & 0x80);
  w[2] = RSHIFT_WORD(w[2]) | ((w[1] >> 17) & 0x80);
  w[1] = RSHIFT_WORD(w[1]) | ((w[0] >> 17) & 0x80);
  w[0] = RSHIFT_WORD(w[0]) ^ (mask & GHASH_POLYNOMIAL);
# elif SIZEOF_LONG == 8
#define RSHIFT_WORD(x) \
  ((((x) & 0xfefefefefefefefeUL) >> 1) \
   | (((x) & 0x0001010101010101UL) << 15))
  mask = - ((w[1] >> 56) & 1);
  w[1] = RSHIFT_WORD(w[1]) | ((w[0] >> 49) & 0x80);
  w[0] = RSHIFT_WORD(w[0]) ^ (mask & GHASH_POLYNOMIAL);
# else
#  error Unsupported word size. */
# endif
# undef RSHIFT_WORD
#endif /* ! WORDS_BIGENDIAN */
}

/* Sets r <- x * y mod r, using the plain bitwise algorithm from the
   specification. y may be shorter than a full block, missing bytes
   are assumed zero. */
static void
gcm_gf_mul (uint8_t *r, const uint8_t *x, unsigned yn, const uint8_t *y)
{
  uint8_t V[GCM_BLOCK_SIZE];
  uint8_t Z[GCM_BLOCK_SIZE];

  unsigned i;
  memcpy(V, x, sizeof(V));
  memset(Z, 0, sizeof(Z));

  for (i = 0; i < yn; i++)
    {
      uint8_t b = y[i];
      unsigned j;
      for (j = 0; j < 8; j++, b <<= 1)
	{
	  if (b & 0x80)
	    memxor(Z, V, sizeof(V));
	  
	  gcm_gf_shift(V);
	}
    }
  memcpy (r, Z, sizeof(Z));
}

#if GCM_TABLE_BITS
# if WORDS_BIGENDIAN
#  define W(left,right) (0x##left##right)
# else
#  define W(left,right) (0x##right##left)
# endif

#if GCM_TABLE_BITS == 4
static const uint16_t
shift_table[0x10] = {
  W(00,00),W(1c,20),W(38,40),W(24,60),W(70,80),W(6c,a0),W(48,c0),W(54,e0),
  W(e1,00),W(fd,20),W(d9,40),W(c5,60),W(91,80),W(8d,a0),W(a9,c0),W(b5,e0),
};
#elif GCM_TABLE_BITS == 8
static const uint16_t
shift_table[0x100] = {
  W(00,00),W(01,c2),W(03,84),W(02,46),W(07,08),W(06,ca),W(04,8c),W(05,4e),
  W(0e,10),W(0f,d2),W(0d,94),W(0c,56),W(09,18),W(08,da),W(0a,9c),W(0b,5e),
  W(1c,20),W(1d,e2),W(1f,a4),W(1e,66),W(1b,28),W(1a,ea),W(18,ac),W(19,6e),
  W(12,30),W(13,f2),W(11,b4),W(10,76),W(15,38),W(14,fa),W(16,bc),W(17,7e),
  W(38,40),W(39,82),W(3b,c4),W(3a,06),W(3f,48),W(3e,8a),W(3c,cc),W(3d,0e),
  W(36,50),W(37,92),W(35,d4),W(34,16),W(31,58),W(30,9a),W(32,dc),W(33,1e),
  W(24,60),W(25,a2),W(27,e4),W(26,26),W(23,68),W(22,aa),W(20,ec),W(21,2e),
  W(2a,70),W(2b,b2),W(29,f4),W(28,36),W(2d,78),W(2c,ba),W(2e,fc),W(2f,3e),
  W(70,80),W(71,42),W(73,04),W(72,c6),W(77,88),W(76,4a),W(74,0c),W(75,ce),
  W(7e,90),W(7f,52),W(7d,14),W(7c,d6),W(79,98),W(78,5a),W(7a,1c),W(7b,de),
  W(6c,a0),W(6d,62),W(6f,24),W(6e,e6),W(6b,a8),W(6a,6a),W(68,2c),W(69,ee),
  W(62,b0),W(63,72),W(61,34),W(60,f6),W(65,b8),W(64,7a),W(66,3c),W(67,fe),
  W(48,c0),W(49,02),W(4b,44),W(4a,86),W(4f,c8),W(4e,0a),W(4c,4c),W(4d,8e),
  W(46,d0),W(47,12),W(45,54),W(44,96),W(41,d8),W(40,1a),W(42,5c),W(43,9e),
  W(54,e0),W(55,22),W(57,64),W(56,a6),W(53,e8),W(52,2a),W(50,6c),W(51,ae),
  W(5a,f0),W(5b,32),W(59,74),W(58,b6),W(5d,f8),W(5c,3a),W(5e,7c),W(5f,be),
  W(e1,00),W(e0,c2),W(e2,84),W(e3,46),W(e6,08),W(e7,ca),W(e5,8c),W(e4,4e),
  W(ef,10),W(ee,d2),W(ec,94),W(ed,56),W(e8,18),W(e9,da),W(eb,9c),W(ea,5e),
  W(fd,20),W(fc,e2),W(fe,a4),W(ff,66),W(fa,28),W(fb,ea),W(f9,ac),W(f8,6e),
  W(f3,30),W(f2,f2),W(f0,b4),W(f1,76),W(f4,38),W(f5,fa),W(f7,bc),W(f6,7e),
  W(d9,40),W(d8,82),W(da,c4),W(db,06),W(de,48),W(df,8a),W(dd,cc),W(dc,0e),
  W(d7,50),W(d6,92),W(d4,d4),W(d5,16),W(d0,58),W(d1,9a),W(d3,dc),W(d2,1e),
  W(c5,60),W(c4,a2),W(c6,e4),W(c7,26),W(c2,68),W(c3,aa),W(c1,ec),W(c0,2e),
  W(cb,70),W(ca,b2),W(c8,f4),W(c9,36),W(cc,78),W(cd,ba),W(cf,fc),W(ce,3e),
  W(91,80),W(90,42),W(92,04),W(93,c6),W(96,88),W(97,4a),W(95,0c),W(94,ce),
  W(9f,90),W(9e,52),W(9c,14),W(9d,d6),W(98,98),W(99,5a),W(9b,1c),W(9a,de),
  W(8d,a0),W(8c,62),W(8e,24),W(8f,e6),W(8a,a8),W(8b,6a),W(89,2c),W(88,ee),
  W(83,b0),W(82,72),W(80,34),W(81,f6),W(84,b8),W(85,7a),W(87,3c),W(86,fe),
  W(a9,c0),W(a8,02),W(aa,44),W(ab,86),W(ae,c8),W(af,0a),W(ad,4c),W(ac,8e),
  W(a7,d0),W(a6,12),W(a4,54),W(a5,96),W(a0,d8),W(a1,1a),W(a3,5c),W(a2,9e),
  W(b5,e0),W(b4,22),W(b6,64),W(b7,a6),W(b2,e8),W(b3,2a),W(b1,6c),W(b0,ae),
  W(bb,f0),W(ba,32),W(b8,74),W(b9,b6),W(bc,f8),W(bd,3a),W(bf,7c),W(be,be),
};
#else
#error Unsupported table size
#endif
#undef W

/* Like gcm_rightshift, but shifts GCM_TABLE_BITS steps. */
#if GCM_TABLE_BITS == 4

static void
gcm_gf_shift_chunk(uint8_t *x)
{
  unsigned long *w = (unsigned long *) x;
  unsigned long reduce;

  /* Shift uses big-endian representation. */
#if WORDS_BIGENDIAN
# if SIZEOF_LONG == 4
  reduce = shift_table[w[3] & 0xf];
  w[3] = (w[3] >> 4) | ((w[2] & 0xf) << 28);
  w[2] = (w[2] >> 4) | ((w[1] & 0xf) << 28);
  w[1] = (w[1] >> 4) | ((w[0] & 0xf) << 28);
  w[0] = (w[0] >> 4) ^ (reduce << 16);
# elif SIZEOF_LONG == 8
  reduce = shift_table[w[3] & 0xf];
  w[1] = (w[1] >> 4) | ((w[0] & 0xf) << 63);
  w[0] = (w[0] >> 4) ^ (reduce << 48);
# else
#  error Unsupported word size. */
#endif
#else /* ! WORDS_BIGENDIAN */
# if SIZEOF_LONG == 4
#define RSHIFT_WORD(x) \
  ((((x) & 0xf0f0f0f0UL) >> 4)			\
   | (((x) & 0x000f0f0f) << 12))
  reduce = shift_table[(w[3] >> 24) & 0xf];
  w[3] = RSHIFT_WORD(w[3]) | ((w[2] >> 20) & 0xf0);
  w[2] = RSHIFT_WORD(w[2]) | ((w[1] >> 20) & 0xf0);
  w[1] = RSHIFT_WORD(w[1]) | ((w[0] >> 20) & 0xf0);
  w[0] = RSHIFT_WORD(w[0]) ^ reduce;
# elif SIZEOF_LONG == 8
#define RSHIFT_WORD(x) \
  ((((x) & 0xf0f0f0f0f0f0f0f0UL) >> 4) \
   | (((x) & 0x000f0f0f0f0f0f0fUL) << 12))
  reduce = shift_table[(w[1] >> 56) & 0xf];
  w[1] = RSHIFT_WORD(w[1]) | ((w[0] >> 52) & 0xf0);
  w[0] = RSHIFT_WORD(w[0]) ^ reduce;
# else
#  error Unsupported word size. */
# endif
# undef RSHIFT_WORD
#endif /* ! WORDS_BIGENDIAN */
}

/* FIXME: Table should be const. */
static void
gcm_gf_mul_chunk (uint8_t *x, const uint8_t *h, uint8_t table[16][16])
{
  uint8_t Z[GCM_BLOCK_SIZE];
  unsigned i;

  memset(Z, 0, sizeof(Z));

  for (i = GCM_BLOCK_SIZE; i-- > 0;)
    {
      uint8_t b = x[i];

      gcm_gf_shift_chunk(Z);
      memxor(Z, table[b & 0xf], GCM_BLOCK_SIZE);
      gcm_gf_shift_chunk(Z);
      memxor(Z, table[b >> 4], GCM_BLOCK_SIZE);
    }
  memcpy (x, Z, sizeof(Z));
}
#endif /* GCM_TABLE_BITS == 4 */
#endif /* GCM_TABLE_BITS */

/* Increment the rightmost 32 bits. */
#define INC32(block) INCREMENT(4, (block) + GCM_BLOCK_SIZE - 4)

/* Initialization of GCM.
 * @ctx: The context of GCM
 * @cipher: The context of the underlying block cipher
 * @f: The underlying cipher encryption function
 */
void
gcm_set_key(struct gcm_ctx *ctx,
	    void *cipher, nettle_crypt_func f)
{
  memset (ctx->h, 0, sizeof (ctx->h));
  f (cipher, GCM_BLOCK_SIZE, ctx->h, ctx->h);  /* H */
#if GCM_TABLE_BITS
#if GCM_TABLE_BITS == 4
  {
    unsigned i;
    for (i = 0; i < 16; i++)
      {
	uint8_t x;
	x = i << 4;
	gcm_gf_mul(ctx->h_table[i], ctx->h, 1, &x);
      }
  }
#else
  abort();
#endif
#endif /* GCM_TABLE_BITS */
}

/*
 * @length: The size of the iv (fixed for now to GCM_NONCE_SIZE)
 * @iv: The iv
 */
void
gcm_set_iv(struct gcm_ctx *ctx, unsigned length, const uint8_t* iv)
{
  /* FIXME: remove the iv size limitation */
  assert (length == GCM_IV_SIZE);

  memcpy (ctx->iv, iv, GCM_BLOCK_SIZE - 4);
  ctx->iv[GCM_BLOCK_SIZE - 4] = 0;
  ctx->iv[GCM_BLOCK_SIZE - 3] = 0;
  ctx->iv[GCM_BLOCK_SIZE - 2] = 0;
  ctx->iv[GCM_BLOCK_SIZE - 1] = 1;

  memcpy (ctx->ctr, ctx->iv, GCM_BLOCK_SIZE);
  INC32 (ctx->ctr);

  /* Reset the rest of the message-dependent state. */
  memset(ctx->x, 0, sizeof(ctx->x));
  ctx->auth_size = ctx->data_size = 0;
}

static void
gcm_hash(struct gcm_ctx *ctx, unsigned length, const uint8_t *data)
{
  for (; length >= GCM_BLOCK_SIZE;
       length -= GCM_BLOCK_SIZE, data += GCM_BLOCK_SIZE)
    {
      memxor (ctx->x, data, GCM_BLOCK_SIZE);
#if GCM_TABLE_BITS
      gcm_gf_mul_chunk (ctx->x, ctx->h, ctx->h_table);
#else
      gcm_gf_mul (ctx->x, ctx->x, GCM_BLOCK_SIZE, ctx->h);
#endif
    }
  if (length > 0)
    {
      memxor (ctx->x, data, length);
#if GCM_TABLE_BITS
      gcm_gf_mul_chunk (ctx->x, ctx->h, ctx->h_table);
#else
      gcm_gf_mul (ctx->x, ctx->x, GCM_BLOCK_SIZE, ctx->h);
#endif
    }
}

void
gcm_auth(struct gcm_ctx *ctx,
	 unsigned length, const uint8_t *data)
{
  assert(ctx->auth_size % GCM_BLOCK_SIZE == 0);
  assert(ctx->data_size % GCM_BLOCK_SIZE == 0);

  gcm_hash(ctx, length, data);

  ctx->auth_size += length;
}

static void
gcm_crypt(struct gcm_ctx *ctx, void *cipher, nettle_crypt_func *f,
	  unsigned length,
	   uint8_t *dst, const uint8_t *src)
{
  uint8_t buffer[GCM_BLOCK_SIZE];

  if (src != dst)
    {
      for (; length >= GCM_BLOCK_SIZE;
           (length -= GCM_BLOCK_SIZE,
	    src += GCM_BLOCK_SIZE, dst += GCM_BLOCK_SIZE))
        {
          f (cipher, GCM_BLOCK_SIZE, dst, ctx->ctr);
          memxor (dst, src, GCM_BLOCK_SIZE);
          INC32 (ctx->ctr);
        }
    }
  else
    {
      for (; length >= GCM_BLOCK_SIZE;
           (length -= GCM_BLOCK_SIZE,
	    src += GCM_BLOCK_SIZE, dst += GCM_BLOCK_SIZE))
        {
          f (cipher, GCM_BLOCK_SIZE, buffer, ctx->ctr);
          memxor3 (dst, src, buffer, GCM_BLOCK_SIZE);
          INC32 (ctx->ctr);
        }
    }
  if (length > 0)
    {
      /* A final partial block */
      f (cipher, GCM_BLOCK_SIZE, buffer, ctx->ctr);
      memxor3 (dst, src, buffer, length);
      INC32 (ctx->ctr);
    }
}

void
gcm_encrypt (struct gcm_ctx *ctx, void *cipher, nettle_crypt_func *f,
	     unsigned length,
             uint8_t *dst, const uint8_t *src)
{
  assert(ctx->data_size % GCM_BLOCK_SIZE == 0);

  gcm_crypt(ctx, cipher, f, length, dst, src);
  gcm_hash(ctx, length, dst);

  ctx->data_size += length;
}

void
gcm_decrypt(struct gcm_ctx *ctx, void *cipher, nettle_crypt_func *f,
	    unsigned length, uint8_t *dst, const uint8_t *src)
{
  assert(ctx->data_size % GCM_BLOCK_SIZE == 0);

  gcm_hash(ctx, length, src);
  gcm_crypt(ctx, cipher, f, length, dst, src);

  ctx->data_size += length;
}

void
gcm_digest(struct gcm_ctx *ctx, void *cipher, nettle_crypt_func *f,
	   unsigned length, uint8_t *digest)
{
  uint8_t buffer[GCM_BLOCK_SIZE];

  assert (length <= GCM_BLOCK_SIZE);

  ctx->data_size *= 8;
  ctx->auth_size *= 8;

  WRITE_UINT64 (buffer, ctx->auth_size);
  WRITE_UINT64 (buffer + 8, ctx->data_size);

  gcm_hash(ctx, GCM_BLOCK_SIZE, buffer);

  f (cipher, GCM_BLOCK_SIZE, buffer, ctx->iv);
  memxor3 (digest, ctx->x, buffer, length);

  return;
}