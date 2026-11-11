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
Review and refactor these Haskell functions. Reply with the full code. The project's build-depends are `base, text, containers, megaparsec, parsec, attoparsec`; `totpCodeFromText :: Text -> Either String TOTPCode` is defined elsewhere.

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

Source: `wire-server/libs/wire-subsystems/src/Wire/CodeStore/Postgres.hs`

Prompt:
````
Review and refactor this Haskell function. Reply with the full code.

```haskell
lookupMeetingCodes ::
  (PGConstraints r) =>
  [MeetingId] ->
  Sem r (Map MeetingId (Code, Maybe Password))
lookupMeetingCodes mids
  | null mids = pure Map.empty
  | otherwise = do
      keys <-
        Map.fromList
          <$> traverse (\mid -> (,mid) <$> Code.mkKey (CodeReferentMeeting mid)) mids
      rows <-
        V.toList
          <$> runStatement
            (V.fromList (map (postgresMarshall . fst) (Map.toList keys)), postgresMarshall CodeTargetMeeting)
            selectMeetingCodes
      pure $
        Map.fromList
          [ (mid, toCode k (val', ttl, codeReferentFromTarget target' targetId, mPw'))
          | (key, val, ttl, targetId, mPw, target) <- rows,
            Right k <- [postgresUnmarshall key],
            mid <- maybeToList (Map.lookup k keys),
            Right val' <- [postgresUnmarshall val],
            Right target' <- [postgresUnmarshall target],
            Right mPw' <- [traverse postgresUnmarshall mPw]
          ]
  where
    selectMeetingCodes :: Hasql.Statement (Vector Text, Text) (Vector (Text, Text, Int32, UUID, Maybe ByteString, Text))
    selectMeetingCodes =
      [vectorStatement|SELECT
                          key :: text,
                          value :: text,
                          GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (expires_at - now()))))::int4 AS ttl_secs,
                          conversation :: uuid,
                          password :: bytea?,
                          target :: text
                        FROM conversation_codes
                        WHERE key = ANY ($1 :: text[]) AND target = ($2 :: text) AND expires_at > now()
                        |]
```
````

Output:
```
lookupMeetingCodes ::
  (PGConstraints r) =>
  [MeetingId] ->
  Sem r (Map MeetingId (Code, Maybe Password))
lookupMeetingCodes [] = pure Map.empty
lookupMeetingCodes mids = do
  keys <-
    Map.fromList
      <$> traverse (\mid -> (,mid) <$> Code.mkKey (CodeReferentMeeting mid)) mids
  rows <-
    V.toList
      <$> runStatement
        (V.fromList (map (postgresMarshall . fst) (Map.toList keys)), postgresMarshall CodeTargetMeeting)
        selectMeetingCodes
  pure $
    Map.fromList
      [ (mid, toCode k (val', ttl, codeReferentFromTarget target' targetId, mPw'))
      | (key, val, ttl, targetId, mPw, target) <- rows,
        Right k <- [postgresUnmarshall key],
        mid <- maybeToList (Map.lookup k keys),
        Right val' <- [postgresUnmarshall val],
        Right target' <- [postgresUnmarshall target],
        Right mPw' <- [traverse postgresUnmarshall mPw]
      ]
  where
    selectMeetingCodes :: Hasql.Statement (Vector Text, Text) (Vector (Text, Text, Int32, UUID, Maybe ByteString, Text))
    selectMeetingCodes =
      [vectorStatement|SELECT
                          key :: text,
                          value :: text,
                          GREATEST(0, FLOOR(EXTRACT(EPOCH FROM (expires_at - now()))))::int4 AS ttl_secs,
                          conversation :: uuid,
                          password :: bytea?,
                          target :: text
                        FROM conversation_codes
                        WHERE key = ANY ($1 :: text[]) AND target = ($2 :: text) AND expires_at > now()
                        |]
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
