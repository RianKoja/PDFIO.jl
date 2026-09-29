export PDAttachment,
       pdDocGetAttachments,
       pdAttachmentGetName,
       pdAttachmentGetData,
       pdAttachmentExtract,
       pdDocExtractAttachments

using ..Common, ..Cos

"""
```
    PDAttachment
```
A file embedded inside a PDF document. It's either listed in the document level
`EmbeddedFiles` name tree or attached to a page with a `FileAttachment`
annotation.

See [`pdDocGetAttachments`](@ref).
"""
struct PDAttachment
    name::String
    stream::CosObject
end

show(io::IO, att::PDAttachment) = print(io, "PDAttachment(", repr(att.name), ")")

"""
```
    pdAttachmentGetName(att::PDAttachment) -> String
```
Returns the file name of the attachment as recorded in the PDF document. The
name is not sanitized. It should not be used as a path without care. See
[`pdAttachmentExtract`](@ref).
"""
pdAttachmentGetName(att::PDAttachment) = att.name

"""
```
    pdAttachmentGetData(att::PDAttachment) -> Vector{UInt8}
```
Reads and decodes the contents of the attachment.
"""
function pdAttachmentGetData(att::PDAttachment)
    bufstm = get(att.stream)
    try
        return read(bufstm)
    finally
        util_close(bufstm)
    end
end

# Attachment file names are not trusted. Only a plain file name is retained.
function sanitize_filename(name::AbstractString)
    name = String(last(split(replace(name, '\\' => '/'), '/')))
    name = replace(name, r"[\x00-\x1f\x7f<>:\"|?*]" => "_")
    name = strip(name)
    return name in ("", ".", "..") ? "attachment" : String(name)
end

# Returns a path in `dir` that does not exist and is not in `used`.
function unique_path(dir::AbstractString, name::String, used::Set{String})
    base, ext = splitext(name)
    path, i = joinpath(dir, name), 0
    while ispath(path) || path in used
        i += 1
        path = joinpath(dir, string(base, " (", i, ")", ext))
    end
    push!(used, path)
    return path
end

"""
```
    pdAttachmentExtract(att::PDAttachment, dir::AbstractString=".") -> String
```
Writes the attachment into the directory `dir` and returns the path of the file
written. Only the file name part of the attachment name is used. Existing files
are never overwritten. A numeric suffix is added to the file name instead.
"""
function pdAttachmentExtract(att::PDAttachment, dir::AbstractString=".")
    return write_attachment(att, dir, Set{String}())
end

function write_attachment(att::PDAttachment, dir::AbstractString,
                          used::Set{String})
    mkpath(dir)
    path = unique_path(dir, sanitize_filename(att.name), used)
    write(path, pdAttachmentGetData(att))
    return path
end

# The file specification dictionary is resolved to the embedded file stream.
function attachment_from_filespec(cosdoc::CosDoc, fs::CosObject,
                                  fallback::String="attachment")
    fsdict = cosDocGetObject(cosdoc, fs)
    fsdict isa IDD{CosDict} || return nothing
    ef = cosDocGetObject(cosdoc, fsdict, cn"EF")
    ef isa IDD{CosDict} || return nothing
    stm = cosDocGetObject(cosdoc, ef, cn"F")
    stm === CosNull && (stm = cosDocGetObject(cosdoc, ef, cn"UF"))
    stm isa IDD{CosStream} || return nothing
    name = fallback
    for key in (cn"UF", cn"F")
        nobj = cosDocGetObject(cosdoc, fsdict, key)
        if nobj isa CosString
            name = CDTextString(nobj)
            break
        end
    end
    return PDAttachment(name, stm)
end

function collect_nametree!(fn::Function, cosdoc::CosDoc,
                           node::CosTreeNode{String}, visited::Set{Any})
    node.values !== nothing && foreach(kv -> fn(kv...), node.values)
    node.kids === nothing && return
    for kid in node.kids
        kid in visited && continue
        push!(visited, kid)
        kidobj = cosDocGetObject(cosdoc, kid)
        kidobj isa IDD{CosDict} || continue
        collect_nametree!(fn, cosdoc, createTreeNode(String, kidobj), visited)
    end
end

"""
```
    pdDocGetAttachments(doc::PDDoc) -> Vector{PDAttachment}
```
Returns all the files embedded in the document. The files listed in the
`EmbeddedFiles` name tree are followed by the ones attached to the pages with
`FileAttachment` annotations. An embedded file referred in both the places is
returned once. Encrypted documents are not supported.

# Example
```
julia> pdDocGetAttachments(doc)
2-element Vector{PDAttachment}:
 PDAttachment("hello.txt")
 PDAttachment("data.bin")
```
"""
function pdDocGetAttachments(doc::PDDoc)
    cosdoc = pdDocGetCosDoc(doc)
    atts, seen = PDAttachment[], Set{Any}()
    function add!(fs, fallback="attachment")
        att = attachment_from_filespec(cosdoc, fs, fallback)
        att === nothing && return
        # Same embedded file stream can be referenced from multiple places.
        id = att.stream isa CosIndirectObject ?
            (att.stream.num, att.stream.gen) : objectid(att.stream)
        id in seen && return
        push!(seen, id)
        push!(atts, att)
    end

    names = pdDocGetNamesDict(doc)
    if names isa IDD{CosDict}
        ef = cosDocGetObject(cosdoc, names, cn"EmbeddedFiles")
        if ef isa IDD{CosDict}
            root = createTreeNode(String, ef)
            collect_nametree!(cosdoc, root, Set{Any}()) do key, fs
                add!(fs, key)
            end
        end
    end

    for i = 1:pdDocGetPageCount(doc)
        cospage = pdPageGetCosObject(pdDocGetPage(doc, i))
        annots = cosDocGetObject(cosdoc, cospage, cn"Annots")
        annots isa IDD{CosArray} || continue
        for annot in get(annots)
            adict = cosDocGetObject(cosdoc, annot)
            adict isa IDD{CosDict} || continue
            cosDocGetObject(cosdoc, adict, cn"Subtype") === cn"FileAttachment" ||
                continue
            add!(cosDocGetObject(cosdoc, adict, cn"FS"))
        end
    end
    return atts
end

"""
```
    pdDocExtractAttachments(doc::PDDoc, dir::AbstractString=".") -> Vector{String}
```
Extracts all the files embedded in the document into the directory `dir`
(default is the current directory), creating it if required. Returns the paths
of the files written. See [`pdAttachmentExtract`](@ref).

# Example
```
julia> doc = pdDocOpen("invoice.pdf");

julia> pdDocExtractAttachments(doc)
1-element Vector{String}:
 "./invoice.xml"
```
"""
function pdDocExtractAttachments(doc::PDDoc, dir::AbstractString=".")
    used = Set{String}()
    return [write_attachment(att, dir, used) for att in pdDocGetAttachments(doc)]
end
