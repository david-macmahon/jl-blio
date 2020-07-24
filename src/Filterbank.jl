"""
Module for interacting with Filterbank files.

See also:
[`Filterbank.Header`](@ref),
[`read!(io::IO, fbh::Filterbank.Header)`](@ref),
[`write(io::IO, fbh::Filterbank.Header)`](@ref),
[`Array(fbh::Filterbank.Header, nspec::Int=1; dropdims::Bool=false)`](@ref)
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
  write_uint(io, length(s)) + write(io, s)
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
         kw == :nbits         ||
         kw == :nsamples      ||
         kw == :nchans        ||
         kw == :nifs          ||
         kw == :nbeams        ||
         kw == :ibeam
         val = read_int(io)
  # String-values keywords
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
         kw == :nbits         ||
         kw == :nsamples      ||
         kw == :nchans        ||
         kw == :nifs          ||
         kw == :nbeams        ||
         kw == :ibeam
         write_symbol(io, kw) + write_int(io, Int32(val))
  # String-values keywords
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
         kw == :data_size
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
    read!(io::IO, Filterbank.Header)::Filterbank.Header

Read and parse Filterbank header from `io` and populate `fbh`.  Add
`header_size` and `data_size` fields based on header size and file length.

If `io` was at the start of the file, it will be positioned at the start of
data after this function returns.  If `io` was positioned elsewhere, that
position will remain unchanged after this function returns.
"""
function Base.read!(io::IO, fbh::Filterbank.Header)::Filterbank.Header
  # If pos is not 0 then save current pos, rewind and (re-)read the
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

  pos = position(io)
  fbh[:header_size] = pos
  fbh[:data_size] = filesize(io) - pos

  # Restore original position if it was non-zero
  if save_pos != 0
    seek(io, pos)
  end

  fbh
end

# Passing type creates new instance
Base.read!(io::IO, ::Type{Header}) = read!(io, Header())

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

"""
    Array(fbh::Filterbank.Header, nspec::Int=1)
    Array(fbh, nspec=1; dropdims::Bool=true)

Return an uninitialized Array sized for `nspec` spectra of Filterbank data as
specified by metadata in `header`, specifically the `:nchans`, `nifs`, and
`:nbits` fields.  The data type of the Array elements will be `Int8` when
`fbh.nbits == 8` or `Float32` when `fbh.nbits == 32`.

The Array will be dimensioned as [chan, IF, spec] unless `dropdims` is true in
which case any singletone dimensions will be eliminated.
"""
function Base.Array(fbh::Filterbank.Header, nspec::Integer=1;
                    dropdims::Bool=false)::Union{Array{Int8},Array{Float32}}
  nchans = get(fbh, :nchans, 0)
  @assert nchans > 0 "invalid nchans ($nchans)"

  nbits = get(fbh, :nbits, 32)
  @assert nbits == 8 || nbits == 32 "unsupported nbits ($nbits)"

  nifs = get(fbh, :nifs, 1)
  max_spec = 8 * get(fbh, :data_size, 0) ÷ (nchans * nifs * nbits)
  @assert nspec <= max_spec "nspec too big ($nspec > $max_spec)"

  if nbits == 8
    eltype = Int8
  else
    eltype = Float32
  end

  dims = [nchans, nifs, nspec]
  if dropdims
    filter!(x->x!=1, dims)
  end

  Array{eltype}(undef, dims...)
end

"""
    maskdc!(a::Array, ncoarse::Integer)

Mask the center (aka "DC") fine channel of all the coarse channels that span
the first dimentsion of `a`.  `ncoarse` must be the total number of coarse
channels in `a`.
"""
function maskdc!(a::Array{Number}, ncoarse::Integer)::Nothing
  @assert size(a,1) % ncoarse == 0 "invalid ncoarse ($ncoarse)"
  nfpc = size(a,1) ÷ ncoarse
  b = reshape(a, nfpc, :)
  dc = nfpc ÷ 2 + 1
  b[dc, :] = (b[dc-1, :] + b[dc+1, :]) / 2
  nothing
end

end # module Filterbank