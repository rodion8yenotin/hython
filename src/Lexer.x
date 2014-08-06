{
module Lexer where
import Control.Monad.State
import Data.Word
import Codec.Binary.UTF8.String (encode)
}

$digit = 0-9

tokens :-
    -- Whitespace handling
    \n$white*                {startWhite}
    $white+		            ;

    -- Comments
    "#".*                    ;

    -- Integers
    0+                      {\_ s -> return $ Literal (Int 0) }
    [1-9][0-9]*             {\_ s -> return $ Literal (Int $ read s) }
    -- 0[bB][01]+              { \_ s -> return $ Literal
    0[oO][0-9]+             { \_ s -> return $ Literal (Int $ read s) }
    0[xX][0-9a-fA-F]+       { \_ s -> return $ Literal (Int $ read s) }

    -- Strings
    '.*'                     {\_ s -> return $ Literal (String s) }
    \".*\"                   {\_ s -> return $ Literal (String s) }

    -- Booleans
    False                    {\_ s -> return $ Literal (Boolean False) }
    True                     {\_ s -> return $ Literal (Boolean True) }

    -- None
    None                     {\_ s -> return $ Literal None }

    def                         { \_ s -> return $ Keyword "def" }
    return                  { \_ s -> return $ Keyword "return" }

    -- Identifiers
    [a-zA-Z_][a-zA-Z0-9_]*      { \_ s -> return $ Identifier s }

    [=\(\)\,\:\+\-\*\/]         { \_ s -> return $ Punctuation s }



{
data Token
     = Newline
     | Indent
     | Dedent
     | Identifier String
     | Literal Value
     | Punctuation String
     | Keyword String
     | EOF
     deriving (Eq,Show)

data Value
    = Int Integer
    | String String
    | Boolean Bool
    | None
    deriving (Eq, Show)

-- The functions that must be provided to Alex's basic interface
-- The input: last character, unused bytes, remaining string
data AlexInput = AlexInput Char [Word8] String
     deriving Show
alexGetByte :: AlexInput -> Maybe (Word8,AlexInput)
alexGetByte (AlexInput c (b:bs) s) = Just (b,AlexInput c bs s)
alexGetByte (AlexInput c [] [])    = Nothing
alexGetByte (AlexInput _ [] (c:s)) = case encode [c] of
                             	   	(b:bs) -> Just (b, AlexInput c bs s)

alexInputPrevChar :: AlexInput -> Char
alexInputPrevChar (AlexInput c _ _) = c

-- Our state

data ParseState = 
     ParseState {input::AlexInput,
                 indent_stack::[Int],
                 pending_tokens::[Token]}
                 deriving Show

initialState::String -> ParseState
initialState s = ParseState {   input = AlexInput '\n' [] s,
                                indent_stack = [1],
                                pending_tokens = []
                                }

-- Our Parser monad
type P a = State ParseState a

evalP::P a -> String -> a
evalP m s= evalState m (initialState s)

-- Set input

startWhite::Int->String->P Token
startWhite n _ = do
	   s<-get
           let is@(cur:_) = indent_stack s
           when (n>cur) $ do
              put s{indent_stack = n:is,pending_tokens = [Indent]}
           when (n<cur)  $ do
              let (pre,post@(top:_)) = span (> n) is
              if top == n
                then
                  put s{indent_stack = post,
                                    pending_tokens = map (const Dedent) pre}
                else
                  error "Indents don't match"
           return Newline

/*name::n->String->P Token*/
/*identifier _ s = return (ID s)*/

-- Action to read a token
readToken::P Token
readToken = do
          s <- get
          case pending_tokens s of
               t:ts -> do
			put s{pending_tokens = ts}
			return t  
               [] ->  case alexScan (input s) 0 of
                       AlexEOF -> do
                                    rval <- startWhite 1 ""
                                    put s{pending_tokens=(pending_tokens s)++[EOF]}
                                    return rval
                       AlexError _ -> error "!Lexical error"
                       AlexSkip inp' _ -> do    
                          put s{input = inp'}
                          readToken
                       AlexToken inp' n act -> do 
                          let (AlexInput _ _ buf) = input s
                          put s{input = inp'}
                          act n (take n buf)

readtoks::P [Token]
readtoks = do
            t<-readToken
            case t of
              EOF -> return [t]
              _ -> do 
                rest<- readtoks
                return (t:rest)

tokenize::String->[Token]
tokenize s = 
        evalP readtoks s 

lexer :: (Token -> P a) -> P a
lexer cont = readToken >>= cont

}