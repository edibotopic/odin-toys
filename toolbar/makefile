all: clean build

build:
	@echo "Building toolbar example in bin directory"
	@mkdir bin && odin build . -o:speed -out:bin/toolbar

clean:
	@echo "Cleaned bin directory"
	@if [ ./bin/ ]; then \
		rm -rf ./bin/; \
	fi
