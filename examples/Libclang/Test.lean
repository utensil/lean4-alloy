import Libclang

#eval show IO _ from do
    let index : Index := Index.create false
    IO.println "OK: let index = Index.create false"
    let tu : TranslationUnit := index.parse "mock.cpp"
    IO.println "OK: let tu := index.parse \"mock.cpp\""
    let ret : UInt32 := tu.save "mock.cpp.tu"
    IO.println s!"OK: tu.save \"mock.cpp.tu\" returned {ret}"