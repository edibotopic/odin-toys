package main

import "core:flags"
import "core:fmt"
import "core:os"

main :: proc() {

	options :: struct {
		file: os.Handle `args:"pos=0,required,file=r" usage:"Input file."`,
	}

	opt: options

	flags.parse_or_exit(&opt, os.args)

	if data, ok := os.read_entire_file(opt.file); ok {
		fmt.println(string(data))
	} else {
		fmt.println("Failed to read the file.")
	}

}
