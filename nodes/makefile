all: clean build

build:
	@echo "Building game in bin directory"
	@mkdir bin && odin build . -o:speed -out:bin/nodes

clean:
	@echo "Cleaned bin directory"
	@if [ ./bin/ ]; then \
		rm -rf ./bin/; \
	fi
