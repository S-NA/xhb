module Generate.Functions where

import Data.Char
import Data.Maybe

import Control.Applicative

import Control.Exception(assert)

import Data.XCB
import Language.Haskell.Syntax

import HaskellCombinators
import Generate(valueParamName,mapAlt,xImport,mapIdents)
import Generate.Monad
import Generate.Facts

import Control.Monad.Reader
import Control.Monad.Maybe

-- Builds a function for every request in the module
-- Hopefully I'm not duplicating too much between here
-- and the types generation module.

-- | Returns the name of the Haskell module containing the type
-- declarations for a given XCB module.
typesModName :: XHeader -> String
typesModName xhd = typesModuleName $ interCapsName xhd

-- | Returns the name of the Haskell module containing the function
-- definitions for a given XCB module.
functionsModName :: XHeader -> String
functionsModName xhd = functionsModuleName $ interCapsName xhd

-- | Returns the name of an X module in InterCaps.
interCapsName :: XHeader -> String
interCapsName xhd = case xheader_name xhd of
                      Nothing -> ensureUpper $ xheader_header xhd
                      Just name -> name

ensureUpper [] = []
ensureUpper (x:xs) = (toUpper x) : xs

ensureLower [] = []
ensureLower (x:xs) = (toLower x) : xs

-- | Given a list of X modules, returns a list of generated Haskell modules
-- which contain the developer friendly functions for using XHB.
functionsModules :: [XHeader] -> [HsModule]
functionsModules xs = map go xs
    where go :: XHeader -> HsModule
          go xhd =
              let rData = ReaderData xhd xs
              in  runReader (functionsModule xhd) rData

-- | Generates the Haskell functions for using the functionality
-- of the passed in X module.
functionsModule :: XHeader -> Generate HsModule
functionsModule xhd | isCoreModule xhd = buildCore xhd
                    | otherwise = buildExtension xhd

-- | Retuns 'True' if the X module is NOT for an extension.
isCoreModule = isNothing . xheader_xname

buildExtension :: XHeader -> Generate HsModule
buildExtension xhd = do
    let emptyModule = newExtensionModule xhd
        rs = requests xhd
    fns <- declareFunctions rs
    imFns <- doImports xhd
    return $ applyMany (fns ++ imFns) emptyModule

doImports :: XHeader -> Generate [HsModule -> HsModule]
doImports xhd =
    let decs = xheader_decls xhd
    in sequence $ mapMaybe go decs
    
  where go :: XDecl -> Maybe (Generate (HsModule -> HsModule))
        go (XImport name) = return $ xImport name
        go _ = Nothing

-- | Builds a haskel functions module for the passed in xml
-- description.  Assumes it is not for extension requests.
buildCore :: XHeader -> Generate HsModule
buildCore xhd = do
    let emptyModule = newCoreModule xhd
        rs = requests xhd
    fns <- declareFunctions rs
    return $ applyMany fns emptyModule

applyMany = foldr (flip (.)) id

-- Creates a nearly empty Haskell module for the passed-in
-- X module.  Also inserts standard Haskell imports.
newCoreModule :: XHeader -> HsModule
newCoreModule xhd = 
    let name = functionsModName xhd
        mod = mkModule name
    in doQualImports $ doImports mod
 where doImports = applyMany $ map (addImport . mkImport) $
             [typesModName xhd
             , packagePrefix ++ ".Connection.Internal"
             , packagePrefix ++ ".Shared"
             ,"Data.Binary.Put"
             ,"Control.Concurrent.STM"
             ,"Foreign.C.Types"
             ]

       doQualImports = addImport $ mkQualImport $
                         packagePrefix ++ ".Connection.Types"

newExtensionModule :: XHeader -> HsModule
newExtensionModule xhd =
    let name = functionsModName xhd
        mod = mkModule name
    in doHidingImports $ doSomeImports $ doImports mod
 where doImports = applyMany $ map (addImport . mkImport) $
             [typesModName xhd
             , packagePrefix ++ ".Connection.Internal"
             , packagePrefix ++ ".Connection.Extension"
             , packagePrefix ++ ".Connection.Types"
             , "Control.Concurrent.STM"
             , "Foreign.C.Types"
             ]

       doSomeImports = addImport $ mkSomeImport "Data.Binary.Put" ["runPut"]
       doHidingImports = addImport $ mkHidingImport (packagePrefix ++ ".Shared") ["Event", "Error"]

connTyName = packagePrefix ++ ".Connection.Types.Connection"

makeReceipt :: RequestInfo -> [HsStmt]
makeReceipt req | hasReply req = return $
                   mkGenerator (mkPVar "receipt")
                               (mkVar "newEmptyTMVarIO")
                | otherwise = empty

sendRequest :: RequestInfo -> [HsStmt]
sendRequest req | hasReply req = map HsQualifier
                   [foldl1 HsApp $ map mkVar $
                    ["sendRequestWithReply"
                    ,"c"
                    ,"chunk"
                    ,"receipt"
                    ]
                   ,mkVar "return" `HsApp` mkVar "receipt"
                   ]
                | otherwise = map HsQualifier $
                    return $ (mkVar "sendRequest" `HsApp` mkVar "c")
                          `HsApp` mkVar "chunk"

getByteOrder :: HsStmt
getByteOrder = mkLetStmt (mkPVar "bo")
               (mkVar "byteOrderFromConn" `HsApp` mkVar "c")


resultType :: RequestInfo -> HsType
resultType req | hasReply req = foldr1 HsTyApp $
                                [mkTyCon "IO"
                                ,mkTyCon "Receipt"
                                ,replyType req
                                ]
               | otherwise = foldr1 HsTyApp $
                             [mkTyCon "IO"
                             ,unit_tycon
                             ]

replyType :: RequestInfo -> HsType
replyType req = mkTyCon $ replyNameFromInfo req


-- | Declares Haskell functions for an X module.
declareFunctions :: [RequestInfo] -> Generate [HsModule -> HsModule]
declareFunctions rInfos = do
  xhd <- current
  mapM (declareFunction (not $ isCoreModule xhd)) rInfos

-- for core requests, we can do the short form and long form
-- because we don't have to import any other modules
-- | Handles a single request in the core functions module.
declareFunction :: Bool -> RequestInfo -> Generate (HsModule -> HsModule)
declareFunction ext req = do
  tyDec <- typDeclaration
  
  return $ applyMany
   [addDecl tyDec
   ,addDecl fnDeclaration
   ,addExport $ mkExportAbs fnName
   ]
 where fnName = fnNameFromRequest req

       fields = requestFields req
       fieldCount = length fields

       bigCount = 3

       shortMode = fieldCount < bigCount

       typDeclaration :: Generate HsDecl
       typDeclaration | shortMode = shortTypDec
                      | otherwise = longTypDec

       fnDeclaration :: HsDecl
       fnDeclaration | shortMode = shortFnDec
                     | otherwise = longFnDec

       shortTypDec, longTypDec :: Generate HsDecl
       shortTypDec = mkTypeSig fnName [] <$> shortTyp
       longTypDec = return $ mkTypeSig fnName [] longType

       shortTyp = do
         fieldTypes <- fieldsToTypes fields
         return $ foldr1 HsTyFun $
             (mkTyCon connTyName) : fieldTypes ++ [resultType req]
                                

       longType = foldr1 HsTyFun $
                  [mkTyCon connTyName
                  ,mkTyCon  $ request_name req
                  ] ++ [resultType req]


       shortFnDec = mkSimpleFun fnName
                    (map mkPVar shortArgs)
                    (HsDo fnBody)

       longFnDec = mkSimpleFun fnName
                   (map mkPVar ["c", "req"])
                   (HsDo fnBody)

       shortArgs = "c" : fieldsToArgNames fields


       -- constructor plus args
       shortRequestExpr :: HsExp
       shortRequestExpr = 
           foldl1 HsApp $ constructor : map mkVar (fieldsToArgNames fields)

       -- TODO: share constructor name between
       -- generation condebases.
       constructor :: HsExp
       constructor = (HsCon . mkUnQName $ "Mk" ++ request_name req)

       fnBody :: [HsStmt]
       fnBody = concat
                [ makeReceipt req
                , buildRequest
                , serializeRequest
                , sendRequest req
                ]

       buildRequest | shortMode = return $ mkLetStmt
                                 (mkPVar "req")
                                 shortRequestExpr
                    | otherwise = empty

       serializeRequest
           | ext = [ mkGenerator (mkPVar "putAction")
                           (foldl1 HsApp $ map mkVar $
                              ["serializeExtensionRequest"
                              ,"c"
                              ,"req"
                              ]
                           )
                   , mkLetStmt (mkPVar "chunk")
                     (mkVar "runPut" `HsApp` mkVar "putAction")
                   ]
           | otherwise = [ getByteOrder
                         , mkLetStmt (mkPVar "chunk")
                              (applyManyExp
                               [mkVar "runPut"
                               ,mkVar "serialize" `HsApp` mkVar "bo" `HsApp` mkVar "req"
                               ])
                         ]


-- | Fold Haskell expressions together in a right-fold fashion
applyManyExp [] = undefined
applyManyExp [x] = x
applyManyExp (x:xs) = HsApp x $ HsParen $ applyManyExp xs

-- | Maps the fields of a X-struct into argument names to be used
-- in an arg-list for a Haskell function
fieldsToArgNames :: [StructElem] -> [String]
fieldsToArgNames = map mapIdents . mapMaybe fieldToArgName

fieldToArgName :: StructElem -> Maybe String
fieldToArgName (List name _ _) = return name
fieldToArgName (SField name _) = return name
fieldToArgName (ValueParam _ mname _ _) = return $ valueParamName mname
fieldToArgName _ = empty

-- | The types corresponding to the args from "fieldsToArgNames".
fieldsToTypes :: [StructElem] -> Generate [HsType]
fieldsToTypes elems = 
  do Just xs <- runMaybeT $ mapAlt fieldToType elems
     return xs

fieldToType :: StructElem -> MaybeT Generate HsType
fieldToType (SField _ typ) = toHsType typ
fieldToType (List _ typ _) = listType <$> toHsType typ
    where listType t = list_tycon `HsTyApp` t
fieldToType (ValueParam typ _ _ _) = vpType <$> toHsType typ
    where vpType t = mkTyCon "ValueParam" `HsTyApp` t
fieldToType _ = empty

{-
-- | Converts a 'Type' to a 'String' usable by 'mkTyCon'.
-- Currently fails for qualified types.
simpleType :: Type -> Generate String
simpleType QualType{} = error "simpleType: Unexpected qualified type"
simpleType (UnQualType typ) = return $ mapTyNames typ
-}

-- | Extracts the requests from an X module.
requests :: XHeader -> [RequestInfo]
requests = mapMaybe go . xheader_decls
 where go (XRequest name code elems reply) = return $
          RequestInfo name code elems reply
       go _ = empty

data RequestInfo = RequestInfo
    {request_name :: Name
    ,request_code :: Int
    ,request_elems :: [StructElem]
    ,request_reply :: Maybe XReply
    }

-- | Extracts only the fields in a request that must be specified
-- by the library end-user.  That is, padding and such is excluded.
requestFields :: RequestInfo -> [StructElem]
requestFields = filter go . request_elems
 where go List{} = True
       go SField{} = True
       go ValueParam{} = True
       go _ = False

-- | Returns true if a request has a reply
hasReply :: RequestInfo -> Bool
hasReply = not . isNothing . request_reply

-- | For a request, returns what the end-user Haskell function
-- is to be named
fnNameFromRequest :: RequestInfo -> String
fnNameFromRequest = ensureLower . request_name

-- | For a request, returns the name of the Haskell type constructor
-- corresponding to its reply.
replyNameFromInfo :: RequestInfo -> String
replyNameFromInfo req = assert (hasReply req) $
                        replyName $ request_name req
