# Binary AST format (`.avma`)

`.avma` stands for **A**pollo **V**irtual **M**achine **A**rchive.

Such a file stores an already-parsed ApolloVM AST, so a code unit can be loaded
without running a parser. Parsing dominates the cost of loading code;
decoding an image of a ~4 KB program is roughly **11× faster** than parsing it,
and the image is about **two thirds** the size of the source.

Everything here is `Uint8List` in and `Uint8List` out. Reading and writing files
is left to the caller, which is why the library is web-safe and has no
`dart:io` variant.

## File layout

| Offset | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | 4 | `magic` | `\0AVM` — `00 41 56 4D` |
| 4 | 2 | `formatVersion` | uint16 BE. The container revision that wrote this file. |
| 6 | 2 | `minReaderVersion` | uint16 BE. The oldest reader that can decode it correctly. |
| 8 | 4 | `flags` | uint32 BE bitfield. |
| 12 | 4 | `sectionsSize` | uint32 BE. Byte length of the section stream. |
| 16 | … | `sections` | Repeated, until `sectionsSize` bytes are consumed. |
| `T` | 4 | `crc32` | uint32 BE, over bytes `[0, T)`. |
| `T+4` | 2 | `signatureLength` | uint16 BE. `0` when unsigned. |
| `T+6` | … | `signature` | Present when `flags.signed`. |
| … | 4 | `trailerMagic` | `AVM\0` — `41 56 4D 00` |

where `T = 16 + sectionsSize`. The total length is always
`26 + sectionsSize + signatureLength`, so truncation and trailing garbage are
detected structurally, before any integrity arithmetic.

All fixed-width fields are **big-endian**. `Endian.host` is never used.

The extension is a convention only — nothing depends on it. A file is
identified by its `magic`, which is why `apollovm run` works on an image
whatever it was named; `.avma` merely decides the default output name when none
is given.

### Sections

```
sectionId    : LEB128 unsigned
payloadSize  : LEB128 unsigned
payload      : payloadSize bytes
```

| Id | Name | Payload |
| --- | --- | --- |
| `0x00` | `custom` | A LEB128-prefixed name, then arbitrary bytes. Always ignored. |
| `0x01` | `metadata` | Writer version, language, code unit id, namespace. **Required.** |
| `0x02` | `stringTable` | The interned strings the AST indexes into. |
| `0x03` | `typeTable` | The interned `ASTType`s the AST indexes into. |
| `0x04` | `astRoot` | The encoded `ASTRoot`. **Required.** |
| `0x05` | `sourceRef` | Reserved: length and checksum of the originating source. |
| `0x06` | `sectionIndex` | Reserved: offsets and sizes, for random access. |
| `0x07` | `archiveEntry` | One code unit of an archive: a complete nested image. |

Because every section is length-prefixed, a reader **skips any id it does not
know**. That is the whole mechanism by which a file written by a newer ApolloVM
keeps loading in an older one.

### Flags

| Bit | Name | Meaning |
| --- | --- | --- |
| `0x01` | `signed` | A signature is present in the trailer. |
| `0x02` | `hasSectionIndex` | A `sectionIndex` section is present. |
| `0x04` | `hasSourceRef` | A `sourceRef` section is present. |
| `0x08` | `archive` | The file bundles several code units. |

An unknown **flag** bit is *rejected*, unlike an unknown section. A flag changes
how the payload must be interpreted, so ignoring one would mean mis-decoding
rather than merely missing information. Purely additive information belongs in a
new section instead.

## Integrity

The CRC-32 (IEEE, reflected, polynomial `0xEDB88320`) covers the header and
every section, and is verified on every read.

**It detects corruption, not tampering.** Anyone who can modify a file can
recompute the checksum in microseconds. Only a signature made with a key the
attacker does not have makes an image tamper-evident. An unsigned image deserves
exactly as much trust as the source it came from — loading one and running it is
equivalent to running arbitrary code from that source.

Signing is optional and pluggable (`ASTBinarySigner` / `ASTBinaryVerifier`), so
an HMAC, a public-key signature or a hardware key store all fit;
`HmacSha256Signer` is built in. The signature covers everything up to **and
including the CRC**, which is the point: an attacker who edits a section and
recomputes the checksum still fails verification.

Verification defaults:

- The CRC is checked unless `verifyChecksum: false` (for forensics and repair
  tooling, not for loading).
- Signature checking is opt-in. Passing a verifier requires the image to be
  signed and to verify; a signed image read *without* a verifier still loads,
  with `ASTBinaryInfo.isSigned` reporting that a signature was there.

## Compatibility

Two version numbers. `formatVersion` is what the writer emitted;
`minReaderVersion` is the oldest reader that can still make sense of the
payload.

A reader accepts any file whose `minReaderVersion` it satisfies, and refuses one
it does not — loudly, naming both versions, rather than producing a wrong AST.
Three layers of tolerance apply on top:

1. **Unknown sections are skipped.** New capabilities should ship as new
   sections for exactly this reason.
2. **Trailing fields in a known section are ignored**, because each section is
   decoded from a bounded view.
3. **Per-feature gating** — `ASTBinaryReadContext.formatVersion` is available to
   every codec, so a field added in a later revision is read conditionally and
   the older branch is kept forever.

`minReaderVersion` stays at `1` as long as every change is expressible as a new
section, a field appended to the end of an existing one, or a `custom` section.
It is raised only for a change that is genuinely not skippable — reinterpreting
an existing field, compressing the stream, changing the framing, or adding a
semantics-changing flag. **Raising it is a breaking change** and ships only in a
major release.

Node tags are append-only and never reused. A removed tag is recorded in
`ASTNodeTag.retired` rather than becoming available again, so an old image is
diagnosed precisely instead of decoding as whatever took its number.

## Encoding notes

- **Strings** are pooled. Identifiers repeat pervasively in a parsed program, so
  this is where most of the size reduction comes from. Index assignment is
  first-seen order — an implementation detail of the writer, not part of the
  format.
- **Types** are pooled too, and the pool carries a correctness contract: the two
  dozen interned `ASTType` singletons decode back to *the same object*, because
  `ASTConstructorParameterDeclaration.resolveNode` compares against
  `ASTTypeConstructorThis.instance` with `identical`. Nullability is part of the
  pool key, so a nullable use of a type never shares an entry with — or mutates
  — the non-nullable singleton. `ASTTypeVar` is deliberately *never* shared: each
  one is wired to its own initializer and caches the type it infers from it.
- **Enums** are stored **by name**. An index silently mis-decodes every older
  file the moment a member is inserted mid-enum, and with the string pool the
  cost is one byte per occurrence either way.
- **Integers** are a form byte plus an unsigned LEB128 magnitude, not signed
  LEB128. Values beyond 2^53 — which a JavaScript double cannot hold — fall back
  to a decimal string, so a VM-written image stays readable and a `dart2js`
  reader that meets one fails with a clear message rather than silently rounding.
- **`ASTModifiers`** is a single byte: seven flags, one spare bit.
- **Lists** are written as `n + 1`, so `0` means "the list itself was null" — a
  distinction the code generators rely on.

Nothing derivable is stored. Parent links, scope-variable resolution, superclass
and extension targets, and the `this.field` constructor-parameter promotion are
all re-established by one `root.resolveNode(null)` after decoding, exactly as
every grammar does after a parse.

## What is not encoded

Nodes holding live Dart state are refused by the writer, with an error naming
where in the program they were found:

- `ASTExternalFunction`, `ASTExternalClassFunction`, `ASTExternalGetter`,
  `ASTExternalClassGetter` — each holds a Dart closure.
- `ASTValueFunction`, `ASTValueFuture`, `ASTClassInstance`,
  `ASTClassStaticAccessor`, `ASTRuntimeVariable` — runtime values.

All of these are injected by `ApolloExternalFunctionMapper`,
`ApolloExternalGetterMapper` or `ApolloVMCore` at run time and are never
produced by a parser, so a parsed AST does not contain them and the same
bindings are re-injected after a binary load.

`test/unit/apollovm_ast_binary_coverage_test.dart` enforces this: it scans
`lib/src/ast/` and requires every concrete `AST*` class to be registered,
pooled, encoded inline by a parent, or listed as refused with a reason.
