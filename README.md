
# StaRVOOrS (v1.7.4.4)


In order to compile StaRVOOrS you must have installed a Haskell compiler: ghc-7.8.3 or later recommended.

At the time of compiling, you can let cabal doing it for you as follows:

    cabal configure
    cabal build

Note that you will probably have to install the following packages:

 language-java >= 0.2.7

 haxml >= 1.25.3

 split >= 0.2.2

 lens >= 4.15.3

Then, for more recent compilers, use the standard Cabal method of installation:

    cabal update
    cabal install haxml

or
    runhaskell Setup.hs configure [--prefix=...] [--buildwith=...]
    runhaskell Setup.hs build
    runhaskell Setup.hs install

For older compilers, use:

    ./configure [--prefix=...] [--buildwith=...]
    make
    make install

In addition, to use the compiled code you have to download the APIs for KeY and LARVA:

http://cse-212294.cse.chalmers.se/starvoors/files/APIs/StaRVOOrS_APIs.zip
