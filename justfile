default:
    @just run --debug

run *DEBUG:
    @odin run {{DEBUG}} .

build *DEBUG:
    @odin build {{DEBUG}} .

push:
    jj git push && jj git push --remote cb
