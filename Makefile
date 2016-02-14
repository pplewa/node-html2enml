PATH := ./node_modules/.bin:${PATH}

.PHONY : init build

init:
	npm install

build:
	coffee -o lib/ -c src/
