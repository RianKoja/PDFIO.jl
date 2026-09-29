#!/usr/bin/env julia
# Extracts the files embedded in PDF documents into a directory.
#
#   julia --project=<PDFIO dir> bin/pdfio-attachments.jl [-l] [-o DIR] FILE.pdf...
#
# -o DIR  directory to extract the files into (default: current directory)
# -l      only list the attachments

using PDFIO

const USAGE = "usage: pdfio-attachments.jl [-l] [-o DIR] FILE.pdf..."

function usage_error(msg)
    println(stderr, "pdfio-attachments.jl: ", msg)
    println(stderr, USAGE)
    return 2
end

function main(args)
    outdir, list, files = ".", false, String[]
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "-l"
            list = true
        elseif arg == "-o"
            i == length(args) && return usage_error("option -o requires a directory")
            i += 1
            outdir = args[i]
        elseif arg in ("-h", "--help")
            println(USAGE)
            return 0
        elseif startswith(arg, "-")
            return usage_error("unknown option $(escape_string(arg))")
        else
            push!(files, arg)
        end
        i += 1
    end
    isempty(files) && return usage_error("no PDF files given")
    status = 0
    for file in files
        try
            doc = pdDocOpen(file)
            try
                if list
                    # Names come from the PDF: escape any terminal control codes.
                    foreach(a -> println(escape_string(pdAttachmentGetName(a))),
                            pdDocGetAttachments(doc))
                else
                    foreach(println, pdDocExtractAttachments(doc, outdir))
                end
            finally
                pdDocClose(doc)
            end
        catch e
            println(stderr, "$file: ", sprint(showerror, e))
            status = 1
        end
    end
    return status
end

exit(main(ARGS))
