# XDMA Ethernet Driver — DMA Layer Plan

**Source of truth:** AMD PG195 (DMA/Bridge Subsystem for PCI Express, XDMA mode). Do not consult `dma_ip_drivers/XDMA/linux-kernel/xdma/` for design decisions; only PG195.

**HW configuration assumed (confirmed with user):**
- 1 H2C channel, 1 C2H channel
- AXI4-Stream interface on both channels
- MSI-X interrupts
- Scope: DMA layer only (no netdev/NAPI code)

---

## 1. Deliverable

A standalone DMA module that exposes this API to the (future) netdev layer:

```c
struct xdma_dev;
struct xdma_ring;       /* one per direction */

int  xdma_probe(struct pci_dev *pdev, struct xdma_dev **out);
void xdma_remove(struct xdma_dev *xd);

int  xdma_ring_alloc(struct xdma_dev *xd, enum xdma_dir dir,
                     unsigned int nr_desc, struct xdma_ring **out);
void xdma_ring_free(struct xdma_ring *r);

int  xdma_channel_start(struct xdma_ring *r);
void xdma_channel_stop(struct xdma_ring *r);

/* H2C (TX): submit one packet as 1..N scatter/gather entries.
 * Engine is (re)armed if idle. opaque is returned on completion. */
int  xdma_tx_submit(struct xdma_ring *r,
                    const struct xdma_sg *sg, unsigned int nsg,
                    void *opaque);

/* C2H (RX): post one empty buffer. */
int  xdma_rx_post(struct xdma_ring *r, dma_addr_t buf, u32 len, void *opaque);

/* Drain up to `budget` completion events. The callback is invoked once
 * per completed packet on TX and once per completed packet on RX.
 * Returns the number of events drained. */
int  xdma_poll(struct xdma_ring *r, int budget,
               void (*cb)(void *opaque, u32 bytes, bool eop, int err));

/* IRQ handlers per channel (MSI-X thread or top-half). */
irqreturn_t xdma_channel_isr(int irq, void *data);
```

The netdev layer built on top will own skbs, NAPI, queue state, and DMA mapping; this layer owns only descriptor rings, the engine registers, and MSI-X plumbing.

---

## 2. Register map (from PG195)

### 2.0 BAR address format (PG195 §PCIe to DMA Address Format)

Every register access is a 32-bit-aligned read/write at:

```
BAR + (target << 12) | (channel << 8) | byte_offset
```

| Bits | Field |
|---|---|
| 31:16 | Reserved |
| 15:12 | Target |
| 11:8  | Channel |
| 7:0   | Byte offset (bits [1:0] must be 0) |

Seven targets used by this driver:

| Target | BAR offset | Block |
|---|---|---|
| 0x0 | 0x0000 | H2C Channel regs |
| 0x1 | 0x1000 | C2H Channel regs |
| 0x2 | 0x2000 | IRQ block |
| 0x4 | 0x4000 | H2C SGDMA |
| 0x5 | 0x5000 | C2H SGDMA |
| 0x6 | 0x6000 | SGDMA Common |
| 0x8 | 0x8000 | MSI-X Vector Table (PBA at 0x8FE0) |

With one H2C and one C2H channel, Channel is always 0.

### 2.0.1 Identifier registers (per block, offset 0x00)

Read at probe and validated:

| Bits | Field | Expected |
|---|---|---|
| 31:20 | Subsystem identifier | 0x1fc |
| 19:16 | Target | matches block (0x0, 0x1, …) |
| 15    | Stream | 1 for AXI4-Stream (our config) |
| 11:8  | Channel ID Target | 0 for our single-channel setup |
| 7:0   | Version | 0x06 ("2017.1 to current release") |

### 2.1 H2C / C2H Channel registers (targets 0x0, 0x1)

| Offset | Name | Notes |
|---|---|---|
| 0x00 | Channel Identifier | RO; verify at probe |
| 0x04 | Channel Control | RW; see §2.1.1 |
| 0x08 | Channel Control W1S | Write 1 to set bits of 0x04 |
| 0x0C | Channel Control W1C | Write 1 to clear bits of 0x04 |
| 0x40 | Channel Status | RW1C for sticky bits; see §2.1.2 |
| 0x44 | Channel Status W1C | Alternate path to clear status bits |
| 0x48 | Completed Descriptor Count | RO, cumulative since Run=1 |
| 0x4C | Channel Alignments | RO: `addr_alignment[23:16]`, `len_granularity[15:8]`, `address_bits[7:0]` |
| 0x88 | Pollmode Low WB Addr | Unused (we use MSI-X) |
| 0x8C | Pollmode High WB Addr | Unused |
| 0x90 | Channel Interrupt Enable Mask | |
| 0x94 | Channel Interrupt Enable Mask W1S | |
| 0x98 | Channel Interrupt Enable Mask W1C | |

C2H channel has the same offset layout as H2C.

#### 2.1.1 Channel Control (0x04) — bit fields used

| Bit | Name | Set to |
|---|---|---|
| 0 | Run | 1 to start, 0 to stop |
| 1 | ie_descriptor_stopped | 1 |
| 2 | ie_descriptor_completed | 1 (required for IRQ on completion) |
| 3 | ie_align_mismatch | 1 |
| 4 | ie_magic_stopped | 1 |
| 5 | ie_invalid_length | 1 |
| 6 | ie_idle_stopped | 1 (so Status.Idle_stopped sets on clean stop) |
| 13:9 | ie_read_error | 0x1F |
| 18:14 | ie_write_error | 0x1F |
| 23:19 | ie_desc_error | 0x1F |
| 25 | non_inc_mode | 0 (we always use incrementing mode) |
| 26 | pollmode_wb_enable | 0 (MSI-X, not poll) |
| 27 | c2h_st_qm_disable | 0 on C2H (we want per-descriptor stream writeback); ignored on H2C |

All other bits reserved.

#### 2.1.3 Channel Interrupt Enable Mask (0x90) — IRQ gating

Distinct from the `ie_*` bits in Control (0x04). The `ie_*` bits enable *logging* of events into Status (0x40); the `im_*` bits in 0x90 enable the logged event to actually raise an interrupt. **Both must be set** for an MSI-X to fire. The 0x90 bit layout mirrors the Status register, with the same companion W1S (0x94) / W1C (0x98) regs:

| Bits | Field | Set to |
|---|---|---|
| 1 | im_descriptor_stopped | 1 |
| 2 | im_descriptor_completed | 1 |
| 3 | im_align_mismatch | 1 |
| 4 | im_magic_stopped | 1 |
| 5 | im_invalid_length | 1 |
| 6 | im_idle_stopped | 1 |
| 13:9 | im_read_error | 0x1F |
| 18:14 | im_write_error | 0x1F |
| 23:19 | im_desc_error | 0x1F |

#### 2.1.2 Channel Status (0x40) — bit fields consumed

| Bit | Name |
|---|---|
| 0 | Busy (RO) |
| 1 | descriptor_stopped (RW1C) |
| 2 | descriptor_completed (RW1C) |
| 3 | align_mismatch (RW1C) |
| 4 | magic_stopped (RW1C) |
| 5 | invalid_length (RW1C) |
| 6 | idle_stopped (RW1C) |
| 13:9 | read_error[4:0] (RW1C) |
| 18:14 | write_error[4:0] (RW1C) |
| 23:19 | desc_error[4:0] (RW1C) |

Spec note: sticky error bits also auto-reset when Run is re-asserted.

### 2.2 H2C / C2H SGDMA registers (targets 0x4, 0x5)

| Offset | Name |
|---|---|
| 0x00 | SGDMA Identifier |
| 0x80 | Descriptor Low Address |
| 0x84 | Descriptor High Address |
| 0x88 | Descriptor Adjacent (number of additional adjacent descriptors at the head) |
| 0x8C | Descriptor Credits |

These tell the engine where the *first* descriptor of the ring lives and how many descriptors immediately follow it adjacently in memory.

### 2.3 SGDMA Common (target 0x6)

| Offset | Name | Bit layout |
|---|---|---|
| 0x00 | SGDMA Identifier | RO |
| 0x10 | Descriptor Control | bits[19:16] = `c2h_dsc_halt[3:0]` (1 bit per C2H channel — set to halt fetches); bits[3:0] = `h2c_dsc_halt[3:0]` (same for H2C). Default 0. |
| 0x14 | Descriptor Control W1S | |
| 0x18 | Descriptor Control W1C | |
| 0x20 | Descriptor Credit Mode Enable | per-channel; same `c2h[19:16]` / `h2c[3:0]` layout. Set the bit for each channel that uses credits doorbell. |
| 0x24 | SG Descriptor Mode Enable | "Bit descriptions are the same as in SGDMA Descriptor Credit Mode Enable (0x20)." Function not retrieved from web docs — implementing agent should consult PG195 PDF before deciding whether to set; a safe default is to leave at 0. |
| 0x28 | SG Descriptor Mode Enable W1S/W1C | |

**Run/halt model:** The per-channel Run bit at Channel Control (0x04)[0] starts the engine. The halt bits at SGDMA Common 0x10 are an *additional* per-channel pause control — the driver leaves them at 0 in steady state and may use them to gracefully pause descriptor fetches without clearing Run.

**Append-while-running model (Descriptor Credits):** With the channel's bit set in `Descriptor Credit Mode Enable (0x20)`, the engine only fetches as many descriptors as software has granted credits via writes to `H2C/C2H SGDMA Descriptor Credits (0x8C)`. Each write *adds* credits. Credits clear automatically on the falling edge of Run, or when credit mode is disabled. This is the canonical doorbell mechanism for posting new TX/RX work to a running engine — used in §5.2 / §5.3.

### 2.4 IRQ block (target 0x2)

| Offset | Name |
|---|---|
| 0x00 | IRQ Block Identifier |
| 0x10 | Channel Interrupt Enable Mask |
| 0x14 | Channel Interrupt Enable Mask W1S |
| 0x18 | Channel Interrupt Enable Mask W1C |
| 0x44 | Channel Interrupt Request (RO) |
| 0x4C | Channel Interrupt Pending (RO) |
| 0xA0 | Channel Vector Number 0 |
| 0xA4 | Channel Vector Number 1 |

Bit layout per PG195:
- In the Channel mask/request/pending regs, H2C bits start at bit 0 and C2H bits start at `NUM_H2C_CHNL`. With our config (1+1): **H2C0 = bit 0, C2H0 = bit 1**.
- In `Channel Vector Number (0xA0)`, 5 bits per channel. With `NUM_H2C_Channel=1`: H2C0 MSI-X vector at bits [4:0], C2H0 MSI-X vector at bits [12:8]. Bits [20:16] and [28:24] are unused slots.

---

## 3. Descriptor format (PG195 §Descriptors)

32 bytes, 32-byte aligned. Pack as a packed struct:

```c
struct xdma_desc {
    __le32 control;    /* [31:16]=magic=0xad4b, [13:8]=nxt_adj, [7:0]=control */
    __le32 len;        /* [27:0] length in bytes */
    __le64 src_adr;    /* H2C: host source buffer.
                        * C2H stream: metadata writeback address (per-desc 8B slot). */
    __le64 dst_adr;    /* C2H stream: host destination buffer. H2C: unused. */
    __le64 nxt_adr;    /* next descriptor address */
} __packed;            /* sizeof == 32 */
```

PG195 §Descriptors note on Src_adr: *"Source address for H2C and memory mapped transfers. Metadata writeback address for C2H transfers."* This is the field that supplies the per-descriptor C2H stream writeback address — there is no separate channel register for it.

Control byte (low 8 bits of `control`):
- bit 0: Stop — fetch halts after this descriptor
- bit 1: Completed — raises IRQ (with ie_descriptor_completed) on finish
- bit 4: EOP — asserts `tlast` on AXI-Stream for this descriptor's last beat

Magic: 0xad4b in bits [31:16].

Adjacency: `nxt_adj` in bits [13:8] = number of *additional* adjacent descriptors after `nxt_adr`.

Constraints (must be enforced by ring builder):
1. Each descriptor 32-byte aligned.
2. A run of adjacent descriptors must not cross a 4 KiB boundary.
3. Max 32 adjacent descriptors per *request*; max 64 per *block*.
4. `Stop` may only be set on the last descriptor of a block.

---

## 4. Ring data structure

One ring per direction. Allocate with `dma_alloc_coherent` to keep descriptor memory uncached-coherent.

```c
struct xdma_ring {
    struct xdma_dev    *xd;
    enum xdma_dir       dir;            /* H2C or C2H */

    /* Descriptor ring */
    struct xdma_desc   *desc;           /* CPU virtual */
    dma_addr_t          desc_phys;
    unsigned int        nr;             /* power of 2 */
    unsigned int        mask;           /* nr - 1 */
    unsigned int        prod;           /* sw producer (next slot to fill) */
    unsigned int        cons;           /* sw consumer (next slot to reclaim) */

    /* Per-slot shadow state — not visible to HW */
    void              **opaque;         /* opaque[nr] */
    u8                 *is_eop;         /* marks packet boundaries (TX) */

    /* C2H stream per-descriptor writeback array (RX only) — see §5.3 */
    struct xdma_c2h_wb *wb;             /* wb[nr], 8B each */
    dma_addr_t          wb_phys;

    /* Register block pointers */
    void __iomem       *ch_regs;        /* H2C or C2H channel regs */
    void __iomem       *sg_regs;        /* H2C or C2H SGDMA regs */

    /* Synchronization */
    spinlock_t          lock;           /* producer side */

    int                 msix_vec;       /* 5-bit vector number */
    int                 irq;            /* Linux IRQ */
};
```

### 4.1 Ring sizing and adjacency chaining

- Choose `nr` = a power of 2, e.g. 256 for TX and 1024 for RX. Size rounded up to whole pages.
- At init, walk all slots and populate `nxt_adr` to point at `slot (i+1) mod nr`, with `nxt_adj` computed as follows:
  - For each slot `i`, let `k` = number of descriptors immediately following slot `i+1` that are physically adjacent AND lie in the same 4 KiB page AND do not exceed 31 (so `k+1 ≤ 32`).
  - Set `nxt_adj = k` at slot `i`.
  - The wrap slot (`i = nr-1`) has `nxt_adj = 0` — wrap breaks adjacency.
- Since all descriptors sit in a single DMA-coherent block, adjacency only breaks at 4 KiB page boundaries and at the wrap.

### 4.2 Why a ring with credits doorbell

PG195 lets the engine walk any graph via `nxt_adr`. We use a circular ring with descriptor-credits gating:
- Program SGDMA Desc Low/High/Adjacent **once** at channel start.
- Leave Run=1 permanently.
- Enable credit mode for the channel in `Descriptor Credit Mode Enable (0x20)` at start.
- Never set `Stop` in steady state — flow is controlled by credits. The engine fetches exactly as many descriptors as credits have been granted, then pauses without clearing Run.
- Each `tx_submit` / `rx_post` writes the count of new descriptors to `SGDMA Descriptor Credits (0x8C)`. This race-free doorbell removes any need to rewrite live descriptors.

### 4.3 C2H per-descriptor writeback array

Allocate `nr * 8` bytes of DMA-coherent memory contiguous with (or alongside) the C2H descriptor ring. For each C2H descriptor `i`, set `desc[i].src_adr = wb_phys + i*8`. The 8-byte writeback slot has the layout from §5.4 (WB Magic 0x52b4, EOP, Length).

PG195 constraint: *"C2H Streaming writeback address cannot cross 4K boundary."* Since each writeback entry is 8 bytes (well below 4 KiB), this is automatically satisfied for any individual entry; the constraint applies per-entry, not to the whole array.

---

## 5. H2C (TX) submission path

### 5.1 Channel arming (one-time, at start)

Done once when the channel is brought up; not repeated per packet.

1. Confirm Channel Status (0x40).Busy == 0; W1C all status bits via 0x44.
2. Build the ring (§4) — descriptors are zero-length placeholders with `nxt_adr`/`nxt_adj` chained but no work in `len`/`src_adr`/`dst_adr`.
3. Set the H2C channel's bit in SGDMA Common `Descriptor Credit Mode Enable (0x20)` — bit 0 for H2C0.
4. Write SGDMA Desc Low (0x80) = low32(desc_phys of slot 0).
5. Write SGDMA Desc High (0x84) = high32(slot 0 phys).
6. Write SGDMA Desc Adjacent (0x88) = nxt_adj at slot 0.
7. Set Channel Control (0x04) Run=1 with all `ie_*` bits from §2.1.1.
8. Set the matching `im_*` bits in Channel IE Mask (0x90) per §2.1.3.

After this, the engine is running but has 0 credits — it will not fetch any descriptors until `tx_submit` writes credits.

### 5.2 Per-packet submit (H2C credits doorbell)

Given `nsg` scatter/gather DMA addresses for one ethernet frame:

1. Acquire `ring->lock`.
2. Check `free = nr - (prod - cons) ≥ nsg`. If not, return `-EBUSY`.
3. For each SG entry `j = 0 .. nsg-1`, starting at slot `prod`:
   - `desc.src_adr = sg[j].dma`
   - `desc.dst_adr = 0`
   - `desc.len = sg[j].len`
   - `desc.control = magic(0xad4b) << 16 | nxt_adj << 8 | ctl`
     - `ctl` bits: `EOP` on last SG entry; `Completed` on last SG entry; `Stop` never
   - `opaque[slot] = (j == nsg-1) ? caller_opaque : NULL`
   - `is_eop[slot] = (j == nsg-1)`
   - advance slot
4. `wmb()` — descriptors visible before credit doorbell.
5. Update `prod`.
6. Write `nsg` to H2C SGDMA Descriptor Credits (0x8C). The engine fetches that many additional descriptors from where it last paused.
7. Release lock.

The engine pauses cleanly when it has consumed all granted credits — it does not walk into stale descriptors. No `Stop` bit gymnastics needed.

### 5.3 C2H (RX) submission path

C2H in AXI-Stream mode is "post empty buffers; engine fills them as frames arrive." PG195 §DMA C2H Stream states:

- Packets can span multiple descriptors.
- A descriptor is closed when it fills OR when AXI-Stream asserts `tlast`.
- For each closed descriptor, the engine writes an 8-byte entry to the address held in that descriptor's **`src_adr`** field. PG195 §Descriptors: *"Source address for H2C and memory mapped transfers. Metadata writeback address for C2H transfers."*

The writeback entry layout (PG195 §DMA C2H Stream):

| Bytes | Field |
|---|---|
| 0..1 | WB Magic (`16'h52b4`) |
| byte 0 bit ?? (offset 0 [16]) | Status.EOP |
| 4..7 | Length[31:0] of data written into this descriptor's buffer |

The C2H stream writeback is gated by Channel Control (0x04) bit 27 `c2h_st_qm_disable`; we leave it 0 (writeback enabled).

#### 5.3.1 RX channel arming (one-time)

Same as §5.1 but using the C2H register block (target 0x1 channel regs, target 0x5 SGDMA), and setting the C2H bit in `Descriptor Credit Mode Enable (0x20)` — that's bit 16 (per the `c2h_dsc_halt[19:16]` layout which mirrors the credit-mode bit positions).

#### 5.3.2 RX submit

Given a DMA buffer `buf` of length `len`:

1. Acquire `ring->lock`.
2. Pick slot `prod`, fail if `prod - cons == nr`.
3. `desc.src_adr = ring->wb_phys + prod * 8`  — the per-descriptor stream writeback slot
4. `desc.dst_adr = buf`
5. `desc.len = len`
6. `desc.control = magic(0xad4b)<<16 | nxt_adj<<8 | Completed(1) | EOP(0) | Stop(0)` — `Completed` set on every RX desc; `EOP` is *reported* by the engine in the writeback's Status[0] bit, not asserted by software.
7. `opaque[slot] = caller_opaque`
8. Zero `ring->wb[prod]` (clear stale magic before HW can write).
9. `wmb()`, advance `prod`.
10. Write 1 to C2H SGDMA Descriptor Credits (0x8C) to grant a credit for this descriptor.
11. Release lock.

### 5.4 RX completion (poll)

The RX engine runs continuously with `Stop` never set. Completions are detected by scanning the writeback array forward from `cons`:

```c
for (i = 0; i < budget; i++) {
    struct xdma_c2h_wb *w = &ring->wb[ring->cons];
    if (le16_to_cpu(w->magic) != 0x52b4) break;   /* not ready */
    rmb();
    u32 bytes = le32_to_cpu(w->length);
    bool eop  = w->status & 1;
    void *op  = ring->opaque[ring->cons];
    w->magic = 0;                                 /* clear for reuse */
    ring->opaque[ring->cons] = NULL;
    ring->cons = (ring->cons + 1) & ring->mask;
    cb(op, bytes, eop, 0);
}
```

The netdev layer stitches together consecutive entries until it sees `eop`, then produces an skb.

---

## 6. MSI-X setup

The XDMA IP provides 32 MSI-X vector entries. Table located at config BAR offset 0x8000 (PBA at 0x8FE0). Linux PCI core manages the table; the driver only configures channel→vector mapping.

1. `pci_alloc_irq_vectors(pdev, 2, 2, PCI_IRQ_MSIX)` — request exactly 2 vectors.
2. Program vector number assignment in `IRQ Block Channel Vector Number (0xA0)`:
   - bits [4:0] = 0 (H2C0 → MSI-X vector 0)
   - bits [12:8] = 1 (C2H0 → MSI-X vector 1)
   - other slots 0
3. Unmask both channel bits in `IRQ Block Channel Interrupt Enable Mask` via W1S at 0x14: write `(1<<0) | (1<<1)` = 0x3. Per PG195: *"The position of the H2C bits always starts at bit 0. The position of the C2H bits is the index above the last H2C index."* With 1+1, that's H2C0=bit 0, C2H0=bit 1.
4. `request_irq` for each vector:
   - vector 0 → H2C ISR (TX completion)
   - vector 1 → C2H ISR (RX completion)
5. Per-channel `ie_*` bits in Channel Control (0x04) and `im_*` bits in Channel IE Mask (0x90) are already set at channel start (§5.1 / §7) — both layers must be enabled for an MSI-X to actually fire.

### 6.1 ISR behavior

The ISR (or threaded-IRQ handler) for a channel does:

1. Read `Channel Status (0x40)`.
2. If any error bit set (read_error/write_error/desc_error/magic_stopped/invalid_length), log and schedule channel reset.
3. W1C the serviced status bits via `Status W1C (0x44)`.
4. Wake the netdev NAPI for this direction. Draining is done entirely in `xdma_poll`.

No need to touch `IRQ Block Channel Interrupt Pending (0x4C)` — MSI-X edges are delivered per-vector and masking is per-channel in the channel IE mask. PG195's `Channel Interrupt Request (0x44)` is for the integrated case; with MSI-X we rely on vector routing.

---

## 7. Init sequence (per channel)

Performed once per direction at probe / `xdma_channel_start`. The H2C path uses target 0x0 channel regs + target 0x4 SGDMA; C2H uses target 0x1 + target 0x5. SGDMA Common is target 0x6, IRQ block is target 0x2.

1. **Validate IP.** Read every block's Identifier register at offset 0x00 and check `[31:20] == 0x1fc`, `[19:16] == expected target`, `[15] == 1` (AXI-Stream), `[7:0] == 0x06`. Abort on mismatch.
2. **Read alignment params.** Read `Channel Alignments (0x4C)`. Store `addr_alignment`, `len_granularity`, `address_bits`. Reject any `submit` whose length isn't a multiple of `len_granularity` or buffer not aligned to `addr_alignment`.
3. **Allocate ring memory** via `dma_alloc_coherent` for the descriptor array. For C2H also allocate the per-descriptor 8-byte writeback array (§4.3).
4. **Chain descriptors.** Fill `nxt_adr` and `nxt_adj` for all `nr` slots respecting the 4 KiB / 32-adjacent rules. For C2H, also pre-populate `desc[i].src_adr = wb_phys + i*8`.
5. **Clear status.** W1C all bits in `Channel Status` via `Status W1C (0x44)`.
6. **Mask channel IRQ.** W1C the channel's bit in `IRQ Block Channel IE Mask` via 0x18.
7. **Halt-bit safe state.** Ensure SGDMA Common `Descriptor Control (0x10)` channel halt bit is 0 (W1C via 0x18 if non-zero).
8. **Enable Descriptor Credit Mode** for this channel by writing the channel bit (H2C0 = bit 0, C2H0 = bit 16) to SGDMA Common `Descriptor Credit Mode Enable (0x20)` via its W1S companion if available; otherwise read-modify-write 0x20.
9. **Assign MSI-X vector** in `IRQ Block Channel Vector Number (0xA0)`: H2C0 in bits [4:0]=0, C2H0 in bits [12:8]=1.
10. **Configure Channel IE Mask (0x90)** with all `im_*` bits from §2.1.3.
11. **Program SGDMA head pointer.** Write Desc Low (0x80), Desc High (0x84), Desc Adjacent (0x88) pointing at slot 0.
12. **Request Linux IRQ** via `request_irq` for the MSI-X vector.
13. **Unmask channel IRQ** in `IRQ Block Channel IE Mask` via W1S at 0x14: bit 0 for H2C0, bit 1 for C2H0.
14. **Write `Channel Control (0x04)`** with Run=1 and all `ie_*` bits from §2.1.1 in one MMIO write. For C2H, ensure bit 27 `c2h_st_qm_disable` = 0; for H2C that bit is don't-care.
15. Mark `ring->running = true`. The engine is now armed with 0 credits and will not fetch any descriptors until the first credit write in `tx_submit`/`rx_post`.

## 8. Shutdown sequence (per channel)

1. Clear Run in `Channel Control (0x04)` (write 0, or W1C bit 0 via 0x0C).
2. Poll `Channel Status (0x40).Busy` until 0, with a timeout (e.g. 1 s). If timeout, set `descriptor_error` flag and force-reset (see §9).
3. Confirm `Idle_stopped` set (if `ie_idle_stopped` was enabled).
4. Mask the channel IRQ via `IRQ Block Channel IE Mask W1C (0x18)`.
5. `free_irq`.
6. W1C all Channel Status bits.
7. `dma_free_coherent` the ring and writeback array.

## 9. Error handling and recovery

On any RW1C status bit in {`magic_stopped`, `invalid_length`, `align_mismatch`, `read_error`, `write_error`, `desc_error`}:

1. Log which bits fired with the channel and current `cons` index.
2. Stop the channel (§8 steps 1–3).
3. Return all in-flight opaques to the caller with error through the completion callback.
4. Reset ring state: `prod = cons = 0`, zero all descriptors (preserving link fields), zero writeback array.
5. Re-arm (§7 steps 9–14). Status sticky bits will auto-clear when Run is re-asserted.

Recoverable vs fatal: the first three errors indicate a driver bug and should be treated as fatal (bring the netdev down). PCIe errors may be transient — retry up to a small bounded count before giving up.

---

## 10. Source layout proposal

New module directory, kept separate from `dma_ip_drivers/` (which we are not using):

```
xdma_eth/
├── Makefile
├── xdma_regs.h          /* register offsets, bit-field macros, struct xdma_desc */
├── xdma_core.h          /* struct xdma_dev, xdma_ring, API declarations */
├── xdma_core.c          /* probe, remove, BAR mapping, Identifier checks */
├── xdma_ring.c          /* ring alloc/free, descriptor chaining */
├── xdma_tx.c            /* H2C submit, Stop-patching append, TX completion */
├── xdma_rx.c            /* C2H post, stream writeback scan */
├── xdma_irq.c           /* MSI-X setup, ISRs */
└── xdma_sysfs.c         /* optional debug attributes (defer) */
```

---

## 11. Items the implementing agent MUST verify from PG195 before writing code

These were not fully retrievable from the web pages I accessed. Read the PDF version to confirm.

1. **BAR register-map formula** — how target IDs 0x0, 0x1, 0x2, 0x4, 0x5, 0x6 map to byte offsets inside the config BAR. (§Register Space / §PCIe to AXI-Lite Master.)
2. **C2H stream per-descriptor writeback address programming** — which register(s) carry the base address of the writeback array described in §DMA C2H Stream. This gates the entire RX path. See §5.3 above.
3. **SGDMA Common Descriptor Control (0x10)** bit definitions — whether there is a per-channel enable that must be set in addition to Channel Control.Run.
4. **SG Descriptor Mode Enable (0x24/0x28)** bit definitions — whether AXI-Stream mode requires a particular write here at init.
5. **Channel Interrupt Enable Mask (0x90)** vs Channel Control `ie_*` bits — which set actually gates the MSI-X delivery (some XDMA generations use one, some both).
6. **Appending to a running channel** — whether Descriptor Credits mode (SGDMA 0x8C + Common 0x20) is the intended race-free doorbell for TX, or whether the Stop-patching scheme in §5.2 is the canonical approach. If Credits mode is supported and clean, prefer it — it removes the need to rewrite live descriptors.
7. **Identifier register expected values** — the exact magic to verify per block at probe time.
8. **Initial Setup For H2C and C2H Transfers** section — I could not retrieve it. If the PDF contains a canonical ordered sequence that differs from §7 above, prefer the PDF.
9. **MSI-X table location and count** — §MSI and MSI-X Interrupts mentions "MSI-X Vector Table and PBA (0x8)" as a target; confirm whether our driver needs to touch it directly or whether PCI core handles it (usually the latter).

---

## 12. Test plan

The implementing agent should include at minimum:

1. **Loopback test**: configure the RTL to wire H2C AXI-Stream output directly to C2H AXI-Stream input, then post RX buffers, submit TX packets, and verify RX matches.
2. **Ring-wrap test**: submit > `nr` descriptors across multiple arms to exercise the wrap-adjacency break.
3. **Error-injection test**: corrupt the magic field in a descriptor and confirm `magic_stopped` recovery works.
4. **MSI-X liveness**: fill TX ring, confirm one IRQ per `Completed`-tagged descriptor (or per batch if IRQ coalescing ends up being added later).
