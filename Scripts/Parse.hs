{-
  The XML files are parsed as if they were X Protocol
  description files used by XCB.

  The internal data-structures created from the parsing are
  pretty-printed to a file per input file.

  Antoine Latter
  aslatter@gmail.com
 -}


import FromXML
import Pretty
import Types

import System.IO
import System.Environment
import System.Exit

import System.FilePath

main = do
  fps <- getArgs
  xheaders <- fromFiles fps
  writeHeaders xheaders

writeHeaders :: [XHeader] -> IO ()
writeHeaders = sequence_ . map writeHeader

writeHeader :: XHeader -> IO ()
writeHeader xhd =
    let fname = outdir </> xname <.> "out"
        xname = getHeaderName xhd
        outString = pretty xhd
    in writeFile fname outString

outdir = "parsed"

getHeaderName (XHeader name _ _) = name
