.PHONY: build freetype run clean

build:
	v -enable-globals .

freetype:
	v -enable-globals -d use_freetype .

run: build
	./ved

clean:
	rm -f ved
