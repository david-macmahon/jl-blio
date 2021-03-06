"""
Module for interacting with Filterbank files.

See also:
[`Filterbank.Header`](@ref),
[`read!(io::IO, fbh::Filterbank.Header)`](@ref),
[`read(io::IO, ::Type{Filterbank.Header})`](@ref),
[`write(io::IO, fbh::Filterbank.Header)`](@ref),
[`Array(fbh::Filterbank.Header, nspec::Int=1; dropdims::Bool=false)`](@ref)
[`chanfreq(fbh::Filterbank.Header, chan::Real)`](@ref)
[`chanfreqs(fbh::Filterbank.Header, chans::AbstractRange)`](@ref)
[`maskdc!(a::Array{Number}, ncoarse::Integer)`](@ref)
"""
module Filterbank

export Header
export read_int
export read_uint
export read_double
export read_string
export read_symbol
export read_angle
export write_int
export write_uint
export write_double
export write_string
export write_symbol
export write_angle
export read_header_item
export write_header_item
export maskdc!

using OrderedCollections

"""
Type used to hold a Filterbank header.  Acts very much like an OrderedDict.
"""
struct Header <: AbstractDict{Symbol, Any}
  # OrderedDict that holds the header key=value pairs
  dict::OrderedDict{Symbol, Any}

  function Header()::Header
    new(OrderedDict())
  end
end

function Base.setindex!(h::Header, val::Any, key::Symbol)
  setindex!(getfield(h, :dict), val, key)
end

function Base.setindex!(h::Header, val::Any, key::AbstractString)
  setindex!(h, val, Symbol(lowercase(key)))
end

function Base.getindex(h::Header, key::Symbol)
  getindex(getfield(h, :dict), key)
end

function Base.getindex(h::Header, key::AbstractString)
  getindex(h, Symbol(lowercase(key)))
end

function Base.get(h::Header, key::Symbol, default=nothing)
  get(getfield(h, :dict), key, default)
end

function Base.get(h::Header, key::AbstractString, default=nothing)
  get(h, Symbol(lowercase(key)), default)
end

function Base.getproperty(h::Header, sym::Symbol)
  get(h, sym, nothing)
end

function Base.length(h::Header)
  length(getfield(h, :dict))
end

function Base.propertynames(h::Header)
  Tuple(keys(getfield(h, :dict)))
end

function Base.iterate(h::Header, state...)
  iterate(getfield(h, :dict), state...)
end

function Base.empty!(h::Header)
  empty!(getfield(h, :dict))
end

"""
Reads a native-endian Int32 from `io`
"""
read_int(io::IO)::Int32 = ltoh(read(io, Int32))

"""
Reads a native-endian UInt32 from `io`
"""
read_uint(io::IO)::UInt32 = ltoh(read(io, UInt32))

"""
Reads a native-endian Float64 (aka double) from `io`
"""
read_double(io::IO)::Float64 = ltoh(read(io, Float64))

"""
Reads a filterbank header string
"""
read_string(io::IO)::String = String(read(io, read_uint(io)))

"""
Reads a filterbank header string as a Symbol
"""
read_symbol(io::IO)::Symbol = Symbol(read(io, read_uint(io)))

"""
Reads a native-endian Float64 (aka double) in ddmmss.s (or hhmmss.s) format and
then converts to degrees (or hours).  This is primarily used to read `src_raj`
and `src_dej` header values.
"""
function read_angle(io)::Float64
  angle = read_double(io)
  negative = (angle < 0.0)
  angle = abs(angle)

  dd = angle ÷ 10000
  angle -= 10000 * dd
  mm = angle ÷ 100
  ss = angle - 100 * mm
  dd += mm/60.0 + ss/3600.0 
  negative ? -dd : dd
end

"""
# Writes `i` to `io` with native endianess.
"""
write_int(io::IO, i::Int32) = write(io, htol(i))

"""
# Writes `u` to `io` with native endianess.
"""
write_uint(io::IO, u::UInt32) = write(io, htol(u))

"""
# Writes `f` to `io` with native endianess.
"""
write_double(io::IO, f::Float64) = write(io, htol(f))

"""
# Writes `s` to `io` as a filterbank header string
"""
function write_string(io::IO, s::AbstractString)
  write_uint(io, UInt32(length(s))) + write(io, s)
end

"""
# Writes `s` to `io` as a filterbank header string
"""
write_symbol(io::IO, s::Symbol) = write_string(io, String(s))

"""
Converts `f` to ddmmss.s (or hhmmss.s) format and then writes it to `io` with
native endianess.  This is primarily used to write `src_raj` and `src_dej`
header values.
"""
function write_angle(io::IO, v::Float64)
  sign = (v < 0) ? -1 : +1
  v = abs(v)
  dd, frac = divrem(v, 1)
  mm, ss = divrem(60*frac, 1)
  ddmmss = sign * (10000*dd + 100*mm + 60*ss)
  write_double(io, ddmmss)
end

"""
    read_header_item(f::Function, io::IO)

Read a Filterbank header keyword and value from `io`. Call
`f(keyword, value, valpo)`, where `keyword` and `value` are from the
header item and `valpos` is the file position from which the value
was read.  This can be used to update erroneous header values in
place. Return `(keyword, value)`.
"""
function read_header_item(f::Function, io::IO)
  kw = read_symbol(io)
  valpos = position(io)

  if     kw == :HEADER_START; val = nothing
  elseif kw == :HEADER_END; kw = nothing; val = nothing
  # Integer-valued keywords
  elseif kw == :telescope_id  ||
         kw == :machine_id    ||
         kw == :data_type     ||
         kw == :barycentric   ||
         kw == :pulsarcentric ||
         kw == :nbeams        ||
         kw == :ibeam
         val = read_int(io)
  # Unsigned integer-valued keywords
  # These 32-bit values are used for calculating sizes/dimensions so they must
  # be positive.  To maximize the range, they are read as UInt32 and then
  # converted to Int64.
  elseif kw == :nbits         ||
         kw == :nsamples      ||
         kw == :nchans        ||
         kw == :nifs
         val = Int64(read_uint(io))
  # String-valued keywords
  elseif kw == :rawdatafile   ||
         kw == :source_name
         val = read_string(io)
  # Double-valued
  elseif kw == :az_start      ||
         kw == :za_start      ||
         kw == :tstart        ||
         kw == :tsamp         ||
         kw == :fch1          ||
         kw == :foff          ||
         kw == :refdm         ||
         kw == :period
         val = read_double(io)
  # Double-valued, angle split
  elseif kw == :src_raj       ||
         kw == :src_dej
         val = read_angle(io)
  # Unsupported keywords
  elseif kw == :FREQUENCY_START ||
         kw == :fchannel        ||
         kw == :FREQUENCY_END
    error("unsupported keyword ($kw)")
  else
    error("unknown keyword ($kw)")
  end

  if !isnothing(kw)
    f(kw, val, valpos)
  end

  (kw, val)
end

"""
    read_header_item(io::IO)

Call [`read_header_item(f::Function, io::IO)`](@ref) with `io` and
a no-op function for `f`.  Return `(keyword, value)`.
"""
function read_header_item(io::IO)
  read_header_item((x...)->nothing, io)
end

"""
    write_header_item(io::IO, kw::Symbol, val=nothing)

Writes Filterbank header item `kw` and `val` to `io`.  A value must be passed
for all keywords other than `:HEADER_START` and `:HEADER_END`.
"""
function write_header_item(io::IO, kw::Symbol, val=nothing)
  # Special keywords
  if     kw == :HEADER_START  ||
         kw == :HEADER_END
         write_symbol(io, kw)
  # Integer-valued keywords
  elseif kw == :telescope_id  ||
         kw == :machine_id    ||
         kw == :data_type     ||
         kw == :barycentric   ||
         kw == :pulsarcentric ||
         kw == :nbeams        ||
         kw == :ibeam
         write_symbol(io, kw) + write_int(io, Int32(val))
  # Unsigned integer-valued keywords
  # See comments in read_header_item
  elseif kw == :nbits         ||
         kw == :nsamples      ||
         kw == :nchans        ||
         kw == :nifs
         write_symbol(io, kw) + write_uint(io, UInt32(val))
  # String-valued keywords
  elseif kw == :rawdatafile   ||
         kw == :source_name
         write_symbol(io, kw) + write_string(io, String(val))
  # Double-valued
  elseif kw == :az_start      ||
         kw == :za_start      ||
         kw == :tstart        ||
         kw == :tsamp         ||
         kw == :fch1          ||
         kw == :foff          ||
         kw == :refdm         ||
         kw == :period
         write_symbol(io, kw) + write_double(io, Float64(val))
  # Double-valued, angle split
  elseif kw == :src_raj       ||
         kw == :src_dej
         write_symbol(io, kw) + write_angle(io, Float64(val))
  # Ignored "convenience" keywords
  elseif kw == :header_size   ||
         kw == :data_size     ||
         kw == :sample_size   ||
         kw == :nsamps
         # Ignored
  # Unsupported keywords
  elseif kw == :FREQUENCY_START ||
         kw == :fchannel        ||
         kw == :FREQUENCY_END
    @warn "unsupported keyword" kw
  else
    @warn "unknown keyword" kw
  end
end

"""
    read!(io::IO, fbh::Filterbank.Header)::Filterbank.Header

Read and parse Filterbank header from `io` and populate `fbh`.  Add
`header_size` and `data_size` fields based on header size and file length.

If `io` was at the start of the file, it will be positioned at the start of
data after this function returns.  If `io` was positioned elsewhere, that
position will remain unchanged after this function returns.

This function adds some additional unofficial "convenience" fields to the
returned Header:
- `:header_size`: number of bytes in header
- `:data_size`: number of bytes of data
- `:sample_size`: size of a single time sample (all channels, all IFs)
- `:nsamps`: data size divided by sample size
The calculated `:nsamps` field should match any `:nsamples` field in the
header.  The `:nsamples` field is an optional header, but it is official so
using that field for the derived "convenience" value is not desirable.
"""
function Base.read!(io::IO, fbh::Filterbank.Header)::Filterbank.Header
  # If position is not 0 then save current position, rewind and (re-)read the
  # (possibly changed?) header.
  save_pos = position(io)
  if save_pos != 0
    seekstart(io)
  end

  # Make sure we start with a 12 byte keyword
  @assert (read_uint(io) == length("HEADER_START")) "invalid filterbank header"
  seekstart(io)

  kw = read_symbol(io)
  @assert (kw == :HEADER_START) "invalid header_start keyword ($kw)"

  # Remove any existing contents
  empty!(fbh)

  kw, val = read_header_item(io)

  while isa(kw, Symbol)
    fbh[kw] = val
    kw, val = read_header_item(io)
  end

  # Calculate some convenience fields
  fbh[:header_size] = mark(io)
  seekend(io)
  fbh[:data_size] = position(io) - reset(io)
  # If all these sizing fields exist
  if all(k->haskey(fbh, k), [:nchans, :nifs, :nbits])
    # Calculate sample size and number of samples
    # TODO Be smarter about non-multiple of 8 bits per spectrum?
    fbh[:sample_size] = (fbh[:nchans]*fbh[:nifs]*fbh[:nbits] + 7) ÷ 8
    fbh[:nsamps] = fbh[:data_size] ÷ fbh[:sample_size]
  end

  # Restore original position if it was non-zero
  if save_pos != 0
    seek(io, save_pos)
  end

  fbh
end

"""
    read(io::IO, Filterbank.Header)::Filterbank.Header

Create a `Filterbank::Header` object, then call `read!()` to populate it.
"""
Base.read(io::IO, ::Type{Header}) = read!(io, Header())

"""
    write(io::IO, fbh::Filterbank.Header)

Seeks to the beginning of io and writes a Filterbank header from the contents
of `fbh`.
"""
function Base.write(io::IO, fbh::Filterbank.Header)
  seekstart(io)

  write_header_item(io, :HEADER_START)

  for (kw, val) in fbh
    write_header_item(io, kw, val)
  end

  write_header_item(io, :HEADER_END)

  # File position is number of bytes written
  position(io)
end

# This is a type alias for possible GuppiRaw data Arrays
FilterbankArray = Union{Array{Int8},Array{Float32}}

"""
    Array(fbh::Filterbank.Header, nspec::Int=0; <kwargs>)

Return an uninitialized Array sized for `nspec` spectra of Filterbank data as
specified by metadata in `header`, specifically the `:nchans`, `:nifs`, and
`:nbits` fields.  The data type of the Array elements will be `Int8` when
`fbh.nbits == 8` or `Float32` when `fbh.nbits == 32`.

If `nspec` is zero, the Array will be sized to hold up to all spectra from the
file or as many spectra as will fit in `maxmem` bytes, whichever is less.  The
returned Array will hold at least one spectrum (assuming it gets successfuly
allocated), even if that would exceed maxmem.  Files with exceptionally large
numbers of channels may not be usable with this convention and the user will
have to devise their own Array allocation scheme.

The Array will be dimensioned as (nchans, nifs, nspec) unless `dropdims` is
true in which case any singleton dimensions will be eliminated or `nants > 1`
(see below).

# Keyword Arguments
- `dropdims::Bool=false`: drop singleton dimensions
- `maxmem::Int64=1<<32`: limit `nspec` to not more than this many bytes
- `nants`::Int=1: If `nants > 1`, split the `chan` dimension into
   `nchan÷nants` and `nants` dimensions.  It is an error if `nchans` is not a
   multiple of `nants`.  The Array will be dimensioned as (nchans÷nants, nants,
   nifs, nspec).
"""
function Base.Array(fbh::Filterbank.Header, nspec::Integer=0;
                    dropdims::Bool=false,
                    maxmem::Int64=1<<32,
                    nants::Integer=1
                   )::FilterbankArray
  nchans = get(fbh, :nchans, 0)
  @assert nchans > 0 "invalid nchans ($nchans)"
  @assert nants > 0 "invalid nants ($nants)"
  @assert nchans % nants == 0 "nchans ($nchans) must be a multiple of nants ($nants)"

  nbits = get(fbh, :nbits, 32)
  @assert nbits == 8 || nbits == 32 "unsupported nbits ($nbits)"

  nifs = get(fbh, :nifs, 1)
  @assert nifs > 0 "unsupported nifs ($nifs)"

  @assert maxmem >= 0 "maxmem must ne non-negative"

  # Only nbits 8 or 32 are supported, so divide by 8 isn't a problem
  sample_size = nchans * nifs * nbits ÷ 8
  max_spec = get(fbh, :data_size, 0) ÷ sample_size

  # Limit max_spec to maxmem
  if max_spec * sample_size > maxmem
    max_spec = maxmem ÷ sample_size
  end

  if max_spec == 0
    # No data_size(!?) or 1 sample exceeds maxmem
    max_spec = 1
  end

  # nspec <= 0 means max_spec
  if nspec <= 0
    nspec = max_spec
  elseif nspec > max_spec
    @warn "limiting nspec to $max_spec"
    nspec = max_spec
  end

  if nbits == 8
    eltype = Int8
  else
    eltype = Float32
  end

  dims = [nchans, nifs, nspec]
  if dropdims
    filter!(x->x!=1, dims)
  end

  if nants > 1
    prepend!(dims, dims[1] ÷ nants)
    dims[2] = nants
  end

  Array{eltype}(undef, dims...)
end

"""
    maskdc!(a::Array, ncoarse::Integer)

Mask the center (aka "DC") fine channel of all the coarse channels that span
the first dimentsion of `a`.  `ncoarse` must be the total number of coarse
channels in `a`.
"""
function maskdc!(a::FilterbankArray, ncoarse::Integer)::Nothing
  @assert size(a,1) % ncoarse == 0 "invalid ncoarse ($ncoarse)"
  nfpc = size(a,1) ÷ ncoarse
  b = reshape(a, nfpc, :)
  dc = nfpc ÷ 2 + 1
  b[dc, :] = (b[dc-1, :] + b[dc+1, :]) / 2
  nothing
end

end # module Filterbank

export chanfreq
export chanfreqs

"""
    chanfreq(fbh::Filterbank.Header, chan::Real)::Float64

Returns the center frequency of the channel given by `chan` based on the `fch1`
and `foff` fields of `fbh`.  The first channel in the file is considered to be
channel 1 (i.e. `chan` is one-based).
"""
function chanfreq(fbh::Filterbank.Header, chan::Real)::Float64
  @assert haskey(fbh, :fch1) "header has no fch1 field"
  @assert haskey(fbh, :foff) "header has no foff field"
  fbh.fch1 + fbh.foff * (chan-1)
end

"""
    chanfreqs(fbh::Filterbank.Header,
              chans::AbstractRange=1:fbh.nchans)::AbstractRange

Returns the center frequencies of the channels given by `chans` based on the
`fch1`, `foff`, and (in the default case) `nchans` fields of `fbh`.  The first
channel in the file is considered to be channel 1 (i.e.  `chans` are
one-based).
"""
function chanfreqs(fbh::Filterbank.Header)::AbstractRange
  @assert haskey(fbh, :fch1) "header has no fch1 field"
  @assert haskey(fbh, :foff) "header has no foff field"
  @assert haskey(fbh, :nchans) "header has no nchans field"
  range(fbh.fch1, step=fbh.foff, length=fbh.nchans)
end

function chanfreqs(fbh::Filterbank.Header,
                        chans::AbstractRange)::AbstractRange
  range(chanfreq(fbh, first(chans)),
        step=fbh.foff*step(chans),
        length=length(chans)
       )
end
