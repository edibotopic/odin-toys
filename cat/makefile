all: clean build

build:
	@echo "Building cat in bin directory"
	@mkdir bin && odin build . -o:speed -out:bin/cat

clean:
	@echo "Cleaned bin directory"
	@if [ ./bin/ ]; then \
		rm -rf ./bin/; \
	fi
