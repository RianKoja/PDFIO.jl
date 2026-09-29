#!/usr/bin/env julia
# Extracts the files embedded in PDF documents into a directory.
#
#   julia --project=<PDFIO dir> bin/pdfio-attachments.jl [-l] [-o DIR] FILE.pdf...
#
# -o DIR  directory to extract the files into (default: current directory)
# -l      only list the attachments

using PDFIO

function main(args)
    outdir, list, files = ".", false, String[]
    i = 1
    while i <= length(args)
        arg = args[i]
        if arg == "-l"
            list = true
        elseif arg == "-o" && i < length(args)
            i += 1
            outdir = args[i]
        elseif arg in ("-h", "--help")
            println("usage: pdfio-attachments.jl [-l] [-o DIR] FILE.pdf...")
            return 0
        else
            push!(files, arg)
        end
        i += 1
    end
    isempty(files) && (println(stderr, "usage: pdfio-attachments.jl [-l] [-o DIR] FILE.pdf..."); return 2)
    status = 0
    for file in files
        try
            doc = pdDocOpen(file)
            try
                if list
                    foreach(a -> println(pdAttachmentGetName(a)), pdDocGetAttachments(doc))
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
