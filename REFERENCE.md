## HS001.1: Replace partial functions in existing code

### Examples

Input:
```
lastElem :: [Int] -> Int
lastElem xs = last xs

firstJust :: [Maybe Int] -> Int
firstJust ms = fromJust (head ms)
```

Prompt:
````
Review and refactor these Haskell functions. Reply with the full code.

```haskell
lastElem :: [Int] -> Int
lastElem xs = last xs

firstJust :: [Maybe Int] -> Int
firstJust ms = fromJust (head ms)
```
````

Output:
```
lastElem :: [Int] -> Maybe Int
lastElem [] = Nothing
lastElem [x] = Just x
lastElem (_ : xs) = lastElem xs

firstJust :: [Maybe Int] -> Maybe Int
firstJust (m : _) = m
firstJust [] = Nothing
```

## HS001.2: Make the empty case explicit in the type

### Examples

Prompt:
````
Implement this Haskell function so it returns the largest element of the list. Reply with the code only.

```haskell
largest :: [Int] -> Int
```
````

Output:
```
largest :: [Int] -> Maybe Int
largest [] = Nothing
largest xs = Just (maximum xs)
```

## HS002.1: Use megaparsec instead of taking text apart by hand

### Examples

Source: `wire-server/libs/wire-api/src/Wire/API/User/Auth/TOTP.hs`

Input:
```
recoveryCodeFromText :: Text -> Either String RecoveryCode
recoveryCodeFromText t
  | length groups /= 4 || any ((/= 4) . Text.length) groups =
      Left "recovery code must have the shape xxxx-xxxx-xxxx-xxxx"
  | not (all (Text.all (`elem` crockfordAlphabet)) groups) =
      Left "recovery code must be Crockford base32 (no I, L, O, U)"
  | otherwise = Right (RecoveryCode upper)
  where
    upper = Text.toUpper t
    groups = Text.splitOn "-" upper

secondFactorCodeFromText :: Text -> Either String SecondFactorCode
secondFactorCodeFromText t =
  case Text.stripPrefix "totp:" t of
    Just rest -> SFTotp <$> totpCodeFromText rest
    Nothing ->
      case Text.stripPrefix "recovery:" t of
        Just rest -> SFRecovery <$> recoveryCodeFromText rest
        Nothing -> Left "unknown second factor type; expected totp: or recovery:"
```

Prompt:
````
Review and refactor these Haskell functions. Reply with the full code. The project's build-depends are `base, text, containers, megaparsec, parsec`; `totpCodeFromText :: Text -> Either String TOTPCode` is defined elsewhere.

```haskell
recoveryCodeFromText :: Text -> Either String RecoveryCode
recoveryCodeFromText t
  | length groups /= 4 || any ((/= 4) . Text.length) groups =
      Left "recovery code must have the shape xxxx-xxxx-xxxx-xxxx"
  | not (all (Text.all (`elem` crockfordAlphabet)) groups) =
      Left "recovery code must be Crockford base32 (no I, L, O, U)"
  | otherwise = Right (RecoveryCode upper)
  where
    upper = Text.toUpper t
    groups = Text.splitOn "-" upper

secondFactorCodeFromText :: Text -> Either String SecondFactorCode
secondFactorCodeFromText t =
  case Text.stripPrefix "totp:" t of
    Just rest -> SFTotp <$> totpCodeFromText rest
    Nothing ->
      case Text.stripPrefix "recovery:" t of
        Just rest -> SFRecovery <$> recoveryCodeFromText rest
        Nothing -> Left "unknown second factor type; expected totp: or recovery:"
```
````

Output:
```
type Parser = Parsec Void Text

recoveryCodeParser :: Parser RecoveryCode
recoveryCodeParser = do
  g <- group
  gs <- count 3 (char '-' *> group)
  pure (RecoveryCode (Text.toUpper (Text.pack (intercalate "-" (g : gs)))))
  where
    group = count 4 (satisfy (\c -> toUpper c `elem` crockfordAlphabet)) <?> "4 Crockford base32 characters"

secondFactorCodeParser :: Parser SecondFactorCode
secondFactorCodeParser =
  (SFTotp <$> (chunk "totp:" *> (takeRest >>= either fail pure . totpCodeFromText)))
    <|> (SFRecovery <$> (chunk "recovery:" *> recoveryCodeParser))
    <?> "totp: or recovery: prefix"

secondFactorCodeFromText :: Text -> Either String SecondFactorCode
secondFactorCodeFromText = first errorBundlePretty . parse (secondFactorCodeParser <* eof) ""
```

## HS002.2: Use Parsec when megaparsec is not a dependency

### Examples

Source: `wire-server/services/gundeck/migrate-data/src/V1_DeleteApnsVoipTokens.hs`

Input:
```
isVoipArn :: Text -> Bool
isVoipArn arn =
  case Text.splitOn ":" arn of
    ["arn", "aws", "sns", _region, _accountId, topic] ->
      case Text.splitOn "/" topic of
        ("endpoint" : "APNS_VOIP" : _) -> True
        ("endpoint" : "APNS_VOIP_SANDBOX" : _) -> True
        _ -> False
    _ -> False
```

Prompt:
````
Review and refactor this Haskell function. Reply with the full code. The project's build-depends are `base, text, containers, parsec`.

```haskell
isVoipArn :: Text -> Bool
isVoipArn arn =
  case Text.splitOn ":" arn of
    ["arn", "aws", "sns", _region, _accountId, topic] ->
      case Text.splitOn "/" topic of
        ("endpoint" : "APNS_VOIP" : _) -> True
        ("endpoint" : "APNS_VOIP_SANDBOX" : _) -> True
        _ -> False
    _ -> False
```
````

Output:
```
isVoipArn :: Text -> Bool
isVoipArn = isRight . parse voipArn ""

voipArn :: Parser ()
voipArn = do
  _ <- string "arn:aws:sns:"
  _region <- many (noneOf ":") <* char ':'
  _accountId <- many (noneOf ":") <* char ':'
  _ <- string "endpoint/"
  _ <- try (string "APNS_VOIP_SANDBOX") <|> string "APNS_VOIP"
  _ <- optional (char '/' *> many (noneOf ":"))
  eof
```
