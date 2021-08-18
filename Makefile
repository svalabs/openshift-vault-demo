URL ?= localhost:1313

default: hugo

.PHONY: hugo
hugo: clean
	firefox $(URL)
	hugo server -s docs/

.PHONY: clean
clean:
	@rm -rf public/

.PHONY: build
build: clean
	hugo --minify -s docs -d ../public
	firefox public/index.html