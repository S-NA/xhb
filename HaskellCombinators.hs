module HaskellCombinators

    (-- *Morphisms on modules
     addImport
    ,addExport
    ,addDecl
    -- *Constructors, in no particular order
    ,mkModule
    ,mkExportAbs
    ,mkExportAll
    ,mkImport
    ,mkHidingImport
    ,mkQualImport
    ,mkTypeDecl
    ,mkSimpleFun
    ,mkPatBind
    ,mkTypeSig
    ,mkConsMatch
    ,mkLitMatch
    ,mkNumLit
    ,mkNewtype
    ,mkInstDecl
    ,mkQName
    ,mkUnQName
    ,mkPVar
    ,mkTyVar
    ,mkTyCon
    ,mkVar
    ,mkConExp
    ,hsAppMany
    ,mkAsExp
    ,mkDataDecl
    ,mkCon
    ,mkRCon
    ,mkClass
    ,mkGenerator
    ,mkLetStmt
    ) where

import Language.Haskell.Syntax
import Language.Haskell.Pretty

import qualified Data.List as List

-- Example of usage

main = putStrLn $ prettyPrint testHsModule

testHsModule = HsModule dummLoc testModName testModExports testModImports testDecls

testModName = Module "Test.Module"

testModExports = Nothing

testModImports = [mkImport "Foreign"
                 ,mkImport "Data.Monoid"
                 ]

testDecls = [mkTypeSig "testfun" [] (HsTyFun (mkTyCon "Int") (mkTyCon "Int"))
            ,mkSimpleFun "testfun" [HsPWildCard] (HsLit $ HsInt 5)
            ]

-- Wrappers around things in Language.Haskell.Syntax
-- L.H.S is designed to be used as a result of parsing.
-- As I'm going in the other direction, I'd like something
-- slightly simpler.
--
-- For example, most of the time I'll be using identifiers instead
-- of symbols, and so all of the combinators here accept strings
-- instead of HsNames, and assume them to be for indetifiers.

dummLoc = SrcLoc "dummy location" 0 0


-- |Statement of the form ([pattern]  <-  [expression]).
-- Part of a 'do' block or list comprehension.
mkGenerator :: HsPat -> HsExp -> HsStmt
mkGenerator = HsGenerator dummLoc

-- |Statement of the form (let [pattern] = [expression]).
-- part of a 'do' block.
mkLetStmt :: HsPat -> HsExp -> HsStmt
mkLetStmt pat expr = HsLetStmt [HsPatBind dummLoc pat (HsUnGuardedRhs expr) []]

-- |Simple import statement
mkImport str = HsImportDecl dummLoc (Module str) False Nothing Nothing

mkHidingImport :: String -> [String] -> HsImportDecl
mkHidingImport name hidings = HsImportDecl
                dummLoc
                (Module name)
                False
                Nothing
                (Just (True, map (HsIThingAll . HsIdent) hidings)) 

mkQualImport :: String -> HsImportDecl
mkQualImport name = HsImportDecl dummLoc (Module name) True Nothing Nothing

mkTypeSig var context typ = HsTypeSig dummLoc [HsIdent var] (HsQualType context typ)

mkTyCon = HsTyCon . UnQual . HsIdent

mkExportAbs :: String -> HsExportSpec
mkExportAbs = HsEAbs . mkUnQName

mkExportAll :: String -> HsExportSpec
mkExportAll = HsEThingAll . mkUnQName

mkTypeDecl :: String -> [String] -> HsType -> HsDecl
mkTypeDecl nm args ty = HsTypeDecl dummLoc (HsIdent nm) (map HsIdent args) ty

mkPatBind :: HsPat -> HsExp -> HsDecl
mkPatBind pat exp = HsPatBind dummLoc pat (HsUnGuardedRhs exp) []

mkSimpleFun :: String  -- ^name
            -> [HsPat] -- ^args
            -> HsExp   -- ^body
            -> HsDecl
mkSimpleFun name args rhs = HsFunBind
     [HsMatch dummLoc (HsIdent name) args (HsUnGuardedRhs rhs) []]

-- |Makes an choice in a function which returns
-- a value based soley on the input constructor
mkConsMatch :: String -- ^Function name
            -> String -- ^Constructor name
            -> HsExp  -- ^Result expression
            -> HsMatch
mkConsMatch fName cons res
    = HsMatch
       dummLoc
       (HsIdent fName)
       [HsPRec (mkUnQName cons) []]
       (HsUnGuardedRhs res)
       [] -- empty "where" clause

mkLitMatch :: String -- ^Function name
           -> HsLiteral -- ^What to match
           -> HsExp -- ^Result
           -> HsMatch
mkLitMatch fName lit res
    = HsMatch
       dummLoc
       (HsIdent fName)
       [HsPLit lit]
       (HsUnGuardedRhs res)
       [] -- empty where clause

mkNumLit :: Integral n => n -> HsExp
mkNumLit = HsLit . HsInt . fromIntegral

-- |Must be called on a non-empty list.
-- 'hsAppMany [x1, x2, x3 ...] -> x1 `HsApp` x2 `HsApp` x3 ...'
hsAppMany :: [HsExp] -> HsExp
hsAppMany [] = error "hsAppMany called on empty list"
hsAppMany xs = List.foldl1' HsApp xs


mkNewtype :: HsContext
          -> String    -- ^name
          -> [String]  -- ^type args
          -> HsConDecl -- ^constructor
          -> [HsQName] -- ^deriving clause
          -> HsDecl
mkNewtype ctxt nam args con drv =
    HsNewTypeDecl
     dummLoc
     ctxt
     (HsIdent nam)
     (map (HsIdent) args)
     con
     drv

mkInstDecl :: HsContext
           -> HsQName  -- ^Class
           -> [HsType] -- ^Type
           -> [HsDecl] -- ^Function definitions
           -> HsDecl
mkInstDecl ctxt clss args decls =
    HsInstDecl dummLoc ctxt clss args decls

mkQName :: String -- ^Module
        -> String -- ^Identifier
        -> HsQName
mkQName
 mod nm = Qual (Module mod) (HsIdent nm)

mkUnQName :: String -> HsQName
mkUnQName = UnQual . HsIdent

mkPVar :: String -> HsPat
mkPVar = HsPVar . HsIdent

mkTyVar :: String -> HsType
mkTyVar = HsTyVar . HsIdent

mkVar :: String -> HsExp
mkVar = HsVar . UnQual . HsIdent

-- |An indentifier-style data constructor expression.
mkConExp :: String -> HsExp
mkConExp = HsCon . mkUnQName

mkDataDecl :: HsContext
           -> String -- ^Constructor
           -> [String] -- ^Type args
           -> [HsConDecl] -- ^Constructors
           -> [HsQName] -- ^Deriving
           -> HsDecl
mkDataDecl ctx nm args cons drv =
    HsDataDecl
     dummLoc
     ctx
     (HsIdent nm)
     (map HsIdent args)
     cons
     drv

-- |A data constructor declaration.
mkCon :: String -> [HsBangType] -> HsConDecl
mkCon nam typs = HsConDecl dummLoc (HsIdent nam) typs

-- |A record constructor declaration.
mkRCon :: String -> [(String,HsBangType)] -> HsConDecl
mkRCon name fields =
 HsRecDecl
  dummLoc
  (HsIdent name)
  (map (\(f,s) -> ([HsIdent f],s)) fields)


-- |A class declaration
mkClass :: HsContext
        -> String   -- ^Name
        -> [String] -- ^Type vars
        -> [HsDecl] -- ^Function signatures & default definitions
        -> HsDecl
mkClass ctxt name vars = HsClassDecl dummLoc ctxt (HsIdent name) (map HsIdent vars)

-- |Expression with type declaration.
-- You'll probably want to wrap this in parens - the Syntax
-- package doesn't do much about fixities.
mkAsExp :: HsExp -> HsType -> HsExp
mkAsExp exp typ = HsExpTypeSig dummLoc exp (HsQualType [] typ)

-- For building up modules

-- |Creates a module with the given name with no imports,
-- no exports and no declarations.
mkModule :: String  -- ^Name
         -> HsModule
mkModule name = HsModule dummLoc (Module name) Nothing [] []

-- |Adds an export to a module
addExport :: HsExportSpec -> HsModule -> HsModule
addExport ex (HsModule loc name exs ims decls) =
    let exs' = case exs of
                 Nothing -> Just [ex]
                 Just xs -> Just $ xs ++ [ex]
    in HsModule loc name exs' ims decls

-- |Adds an import to a module
addImport :: HsImportDecl -> HsModule -> HsModule
addImport im (HsModule loc name exs ims decls) =
    HsModule loc name exs (ims ++ [im]) decls

-- |Adds a declaration to a module
addDecl :: HsDecl -> HsModule -> HsModule
addDecl decl (HsModule loc name exs ims decls) =
    HsModule loc name exs ims (decls ++ [decl])
