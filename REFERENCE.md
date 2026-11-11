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

## HS002.2: Use Parsec when neither megaparsec nor attoparsec is a dependency

### Examples

Source: `wire-server/services/gundeck/migrate-data/src/V1_DeleteApnsVoipTokens.hs`

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

## HS002.3: Use attoparsec when it is the only parser library available, for `Text` and `ByteString` alike (`Data

### Examples

Source: `wire-server/services/background-worker/src/Wire/DeadUserNotificationWatcher.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code. The project's build-depends are `base, bytestring, containers, attoparsec`.

```haskell
parseDeadQueue :: ByteString -> Maybe (ByteString, ByteString)
parseDeadQueue bs = do
  rest <- BS.stripPrefix "user-notifications." bs
  let (uid, rest') = BS8.break (== '.') rest
  cid <- BS.stripPrefix "." rest'
  guard (not (BS.null uid) && not (BS.null cid) && BS8.notElem '.' cid)
  pure (uid, cid)
```
````

Output:
```
parseDeadQueue :: ByteString -> Maybe (ByteString, ByteString)
parseDeadQueue = either (const Nothing) Just . parseOnly (queue <* endOfInput)
  where
    queue = (,) <$> (string "user-notifications." *> segment) <* char '.' <*> segment
    segment = takeWhile1 (/= '.')
```

## HS002.4: When megaparsec and attoparsec are both available, match the library to the task

### Examples

Source: `wire-server/services/gundeck/migrate-data/src/V1_DeleteApnsVoipTokens.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code. The project's build-depends are `base, text, containers, megaparsec, attoparsec`.

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
isVoipArn = isRight . parseOnly (arn <* endOfInput)
  where
    arn = string "arn:aws:sns:" *> field *> char ':' *> field *> char ':' *> topic
    field = takeWhile (/= ':')
    topic = string "endpoint/" *> (string "APNS_VOIP_SANDBOX" <|> string "APNS_VOIP") *> (char '/' *> field <|> pure "")
```

Prompt:
````
Review and refactor this Haskell function. Reply with the full code. The project's build-depends are `base, text, containers, megaparsec, attoparsec`.

```haskell
parseHostPort :: Text -> Either String (Text, Int)
parseHostPort t =
  case Text.breakOn ":" t of
    ("", _) -> Left "empty host"
    (_, "") -> Left "missing ':' between host and port"
    (host, rest) ->
      case readMaybe (Text.unpack (Text.drop 1 rest)) of
        Just p | p > 0 && p < 65536 -> Right (host, p)
        _ -> Left "port must be a number between 1 and 65535"
```
````

Output:
```
parseHostPort :: Text -> Either String (Text, Int)
parseHostPort = first errorBundlePretty . parse (hostPort <* eof) ""
  where
    hostPort = (,) <$> (takeWhile1P (Just "host") (/= ':') <* char ':') <*> port
    port = do
      p <- L.decimal
      if p > 0 && p < 65536 then pure p else fail "port must be a number between 1 and 65535"
```

Source: `wire-server/libs/wire-api/src/Wire/API/Routes/Bearer.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code. The project's build-depends are `base, bytestring, text, megaparsec, attoparsec`.

```haskell
parseBearer :: ByteString -> Either Text ByteString
parseBearer h =
  case BS.stripPrefix "Bearer " h of
    Just token
      | not (BS.null token) && BS8.notElem ' ' token -> Right token
    _ -> Left "Invalid authorization scheme"
```
````

Output:
```
parseBearer :: ByteString -> Either Text ByteString
parseBearer = first (const "Invalid authorization scheme") . parseOnly (string "Bearer " *> takeWhile1 (/= ' ') <* endOfInput)
```

## HS003.1: Branch on parameters with patterns first, guards second, `if`/`when`/`unless` last

### Examples

Prompt:
````
Review and refactor this Haskell function. Reply with the full code.

```haskell
getContactStatusesImpl ::
  forall r fedM.
  ( Member UserStore r,
    Member ClientStore r,
    Member MlsKeyPackageSubsystem r,
    Member GalleyAPIAccess r,
    Member (Input UserSubsystemConfig) r,
    Member (FederationAPIAccess fedM) r,
    Member TinyLog r,
    RunClient (fedM 'Brig),
    VersionedMonad Version (fedM 'Brig),
    FederationMonad fedM,
    Typeable fedM
  ) =>
  Local UserId ->
  [Qualified UserId] ->
  Sem r (Map (Qualified UserId) ContactStatus)
getContactStatusesImpl self qids
  | null qids = pure mempty -- no need for the whole machinery
  | otherwise = do
      ctx <- contactStatusContextImpl self
      Map.union <$> getLocalStatuses ctx locals <*> getRemoteStatuses ctx remotes
  where
    (locals, remotes) = partitionQualified self (nubOrd qids)

    getLocalStatuses :: ContactStatusContext -> [UserId] -> Sem r (Map (Qualified UserId) ContactStatus)
    getLocalStatuses ctx uids =
      Map.mapKeys (tUntagged . qualifyAs self)
        <$> getLocalContactStatusesImpl ctx uids

    getRemoteStatuses :: ContactStatusContext -> [Remote UserId] -> Sem r (Map (Qualified UserId) ContactStatus)
    getRemoteStatuses ctx rs = do
      remoteResponses <-
        runFederatedConcurrentlyEither rs $ \ruids ->
          -- only keep what was asked for, whatever the remote answers
          (`Map.restrictKeys` Set.fromList (tUnqualified ruids))
            . fold
            <$> for (chunksOf FedBrig.maxContactStatusUsers (tUnqualified ruids)) \chunk ->
              (.statuses) <$> fedClient @'Brig @"get-users-contact-status" (FedBrig.GetContactStatusRequest ctx (unsafeRange chunk))
      Map.unions <$> for remoteResponses \case
        Left (ruids, e) -> do
          Log.warn $
            Log.msg (Log.val "Failed to get contact status from remote backend")
              . Log.field "domain" (domainText (tDomain ruids))
              . Log.field "error" (displayException e)
          pure mempty
        Right rstatuses ->
          pure $
            Map.mapKeys
              (tUntagged . qualifyAs rstatuses)
              (tUnqualified rstatuses)
```
````

Output:
```
getContactStatusesImpl ::
  forall r fedM.
  ( Member UserStore r,
    Member ClientStore r,
    Member MlsKeyPackageSubsystem r,
    Member GalleyAPIAccess r,
    Member (Input UserSubsystemConfig) r,
    Member (FederationAPIAccess fedM) r,
    Member TinyLog r,
    RunClient (fedM 'Brig),
    VersionedMonad Version (fedM 'Brig),
    FederationMonad fedM,
    Typeable fedM
  ) =>
  Local UserId ->
  [Qualified UserId] ->
  Sem r (Map (Qualified UserId) ContactStatus)
getContactStatusesImpl _self [] = pure mempty -- no need for the whole machinery
getContactStatusesImpl self qids = do
  ctx <- contactStatusContextImpl self
  Map.union <$> getLocalStatuses ctx locals <*> getRemoteStatuses ctx remotes
  where
    (locals, remotes) = partitionQualified self (nubOrd qids)

    getLocalStatuses :: ContactStatusContext -> [UserId] -> Sem r (Map (Qualified UserId) ContactStatus)
    getLocalStatuses ctx uids =
      Map.mapKeys (tUntagged . qualifyAs self)
        <$> getLocalContactStatusesImpl ctx uids

    getRemoteStatuses :: ContactStatusContext -> [Remote UserId] -> Sem r (Map (Qualified UserId) ContactStatus)
    getRemoteStatuses ctx rs = do
      remoteResponses <-
        runFederatedConcurrentlyEither rs $ \ruids ->
          -- only keep what was asked for, whatever the remote answers
          (`Map.restrictKeys` Set.fromList (tUnqualified ruids))
            . fold
            <$> for (chunksOf FedBrig.maxContactStatusUsers (tUnqualified ruids)) \chunk ->
              (.statuses) <$> fedClient @'Brig @"get-users-contact-status" (FedBrig.GetContactStatusRequest ctx (unsafeRange chunk))
      Map.unions <$> for remoteResponses \case
        Left (ruids, e) -> do
          Log.warn $
            Log.msg (Log.val "Failed to get contact status from remote backend")
              . Log.field "domain" (domainText (tDomain ruids))
              . Log.field "error" (displayException e)
          pure mempty
        Right rstatuses ->
          pure $
            Map.mapKeys
              (tUntagged . qualifyAs rstatuses)
              (tUnqualified rstatuses)
```

Source: `wire-server/libs/wire-api/src/Wire/API/User/Auth/TOTP.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code. The module enables OverloadedStrings.

```haskell
totpSecretFromBase32 :: Text -> Either String TOTPSecret
totpSecretFromBase32 txt
  | Text.null txt = Left "TOTP secret must not be empty"
  | Text.any (== '=') txt = Left "TOTP secret must be unpadded base32 (RFC 4648)"
  | otherwise = TOTPSecret <$> convertFromBase Base32 (Text.encodeUtf8 padded)
  where
    upper = Text.toUpper txt
    padded = upper <> Text.replicate ((8 - Text.length upper `rem` 8) `rem` 8) "="
```
````

Output:
```
totpSecretFromBase32 :: Text -> Either String TOTPSecret
totpSecretFromBase32 "" = Left "TOTP secret must not be empty"
totpSecretFromBase32 txt
  | Text.any (== '=') txt = Left "TOTP secret must be unpadded base32 (RFC 4648)"
  | otherwise = TOTPSecret <$> convertFromBase Base32 (Text.encodeUtf8 padded)
  where
    upper = Text.toUpper txt
    padded = upper <> Text.replicate ((8 - Text.length upper `rem` 8) `rem` 8) "="
```

Source: `wire-server/services/brig/src/Brig/Options.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code.

```haskell
asciiOnly :: Text -> A.Parser ByteString
asciiOnly t =
  if Text.all Char.isAscii t
    then pure $ Text.encodeUtf8 t
    else fail $ "Expected ascii string only, found: " <> Text.unpack t
```
````

Output:
```
asciiOnly :: Text -> A.Parser ByteString
asciiOnly t
  | Text.all Char.isAscii t = pure $ Text.encodeUtf8 t
  | otherwise = fail $ "Expected ascii string only, found: " <> Text.unpack t
```

Source: `wire-server/services/brig/src/Brig/API/User.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code.

```haskell
guardUserDisplayname ::
  NewUser a ->
  User ->
  ExceptT RegisterError (AppT r) ()
guardUserDisplayname new user =
  when (user.userManagedBy == ManagedByScim) $
    unless (new.newUserDisplayName == user.userDisplayName) $
      throwE RegisterErrorScimDisplayNameMismatch
```
````

Output:
```
guardUserDisplayname ::
  NewUser a ->
  User ->
  ExceptT RegisterError (AppT r) ()
guardUserDisplayname new user
  | user.userManagedBy == ManagedByScim,
    new.newUserDisplayName /= user.userDisplayName =
      throwE RegisterErrorScimDisplayNameMismatch
  | otherwise = pure ()
```

Prompt:
````
Review and refactor this Haskell function. Reply with the full code.

```haskell
registerUser :: UserId -> App ()
registerUser uid = do
  existing <- lookupUser uid
  if isJust existing
    then throwError UserAlreadyExists
    else insertUser uid
```
````

Output:
```
registerUser :: UserId -> App ()
registerUser uid = do
  existing <- lookupUser uid
  if isJust existing
    then throwError UserAlreadyExists
    else insertUser uid
```

Source: `wire-server/libs/wire-subsystems/src/Wire/PaginationState.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code.

```haskell
paginationClause :: (PostgresValue a) => PaginationState a -> Maybe Clause
paginationClause s = case s of
  PaginationSortByName (Just (name, x)) ->
    Just (mkClause "name" name <> mkClause "id" x)
  PaginationSortByCreatedAt (Just (createdAt, x)) ->
    Just (mkClause "created_at" createdAt <> mkClause "id" x)
  PaginationOffset _ -> Nothing
  _ -> Nothing
```
````

Output:
```
paginationClause :: (PostgresValue a) => PaginationState a -> Maybe Clause
paginationClause (PaginationSortByName (Just (name, x))) =
  Just (mkClause "name" name <> mkClause "id" x)
paginationClause (PaginationSortByCreatedAt (Just (createdAt, x))) =
  Just (mkClause "created_at" createdAt <> mkClause "id" x)
paginationClause _ = Nothing
```
