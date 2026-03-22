module Main (main) where

import CddlAiken.Compiler (CompileError (..), compile)
import Data.Text (Text)
import Data.Text.IO qualified as TIO
import System.Directory (createDirectoryIfMissing)
import System.Environment (getArgs)
import System.Exit (exitFailure)
import System.FilePath (takeDirectory, (</>))

main :: IO ()
main = do
  args <- getArgs
  case args of
    ["compile", inputFile, "-o", outputDir] -> do
      src <- TIO.readFile inputFile
      case compile src of
        Left (ParseError err) -> do
          putStrLn $ "Parse error: " ++ err
          exitFailure
        Left (ValidationError err) -> do
          putStrLn $ "Validation error: " ++ err
          exitFailure
        Right files -> do
          mapM_ (writeOutput outputDir) files
          putStrLn $ "Generated " ++ show (length files) ++ " files in " ++ outputDir
    _ -> do
      putStrLn "Usage: cddl-aiken compile <input.cddl> -o <output-dir>"
      exitFailure

writeOutput :: FilePath -> (FilePath, Text) -> IO ()
writeOutput outputDir (path, content) = do
  let fullPath = outputDir </> path
  createDirectoryIfMissing True (takeDirectory fullPath)
  TIO.writeFile fullPath content
  putStrLn $ "  " ++ path
