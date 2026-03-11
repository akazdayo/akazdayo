let
  fieldOrder = [
    "name"
    "url"
    "stars"
    "language"
    "pushedAt"
    "topics"
    "archived"
    "fork"
  ];

  sortAsc = builtins.sort builtins.lessThan;

  fail = message: builtins.throw "repos.nix schema error: ${message}";

  expect = message: condition: if condition then true else fail message;

  isString = value: builtins.typeOf value == "string";
  isInt = value: builtins.typeOf value == "int";
  isBool = value: builtins.typeOf value == "bool";
  isList = value: builtins.typeOf value == "list";

  checkRepoShape =
    repo:
    let
      keys = sortAsc (builtins.attrNames repo);
    in
    expect "repo fields must match the committed whitelist exactly" (keys == sortAsc fieldOrder);

  normalizeRepo =
    repo:
    let
      name = repo.name;
      url = repo.url;
      stars = repo.stars;
      language = if repo.language == null then null else repo.language;
      pushedAt = repo.pushedAt;
      topics = sortAsc repo.topics;
      archived = repo.archived;
      fork = repo.fork;
      checks = [
        (expect "the top-level snapshot entries must be attrsets" (builtins.isAttrs repo))
        (checkRepoShape repo)
        (expect "`name` must be a string" (isString name))
        (expect "`url` must be a string" (isString url))
        (expect "`stars` must be an integer" (isInt stars && stars >= 0))
        (expect "`language` must be null or a string" (language == null || isString language))
        (expect "`pushedAt` must be an ISO 8601 UTC string" (
          isString pushedAt
          && builtins.match "^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$" pushedAt != null
        ))
        (expect "`topics` must be a list of strings" (
          isList repo.topics && builtins.all isString repo.topics
        ))
        (expect "`archived` must be a boolean" (isBool archived))
        (expect "`fork` must be a boolean" (isBool fork))
      ];
      verified = builtins.all (value: value) checks;
    in
    if verified then
      {
        name = name;
        url = url;
        stars = stars;
        language = language;
        pushedAt = pushedAt;
        topics = topics;
        archived = archived;
        fork = fork;
      }
    else
      fail "unreachable repo verification branch";

  repoLessThan =
    left: right: if left.stars != right.stars then left.stars > right.stars else left.name < right.name;

  normalizeRepos =
    repos:
    let
      verified = expect "`repos.nix` must import as a top-level list" (isList repos);
    in
    if verified then
      builtins.sort repoLessThan (map normalizeRepo repos)
    else
      fail "unreachable list verification branch";

  validateRepo =
    repo:
    let
      normalized = normalizeRepo repo;
      verified = builtins.all (value: value) [
        (expect "repo topics must already be sorted asc" (repo.topics == normalized.topics))
        (expect "repo language values must preserve null instead of placeholder strings" (
          repo.language == normalized.language
        ))
      ];
    in
    if verified then normalized else fail "unreachable repo validation branch";

  validateRepos =
    repos:
    let
      normalized = normalizeRepos repos;
      validatedRepos = map validateRepo repos;
      verified = expect "repos must already be ordered by stars desc then name asc" (repos == normalized);
    in
    builtins.deepSeq validatedRepos (
      if verified then normalized else fail "unreachable repos validation branch"
    );

  isReadmeVisible = repo: !repo.fork && !repo.archived;
  readmeFacingRepos = repos: builtins.filter isReadmeVisible (normalizeRepos repos);
in
{
  committedSnapshot = {
    topLevel = "list";
    entryType = "repository";
    fieldWhitelist = fieldOrder;
    fieldOrder = fieldOrder;
  };

  normalization = {
    repoOrder = "stars desc then name asc";
    topicOrder = "asc";
    languageNull = null;
  };

  aggregation = {
    machineReadable = "keep all normalized repositories in the exported list";
    featured = "exclude repos where fork = true or archived = true";
    recent = "exclude repos where fork = true or archived = true";
  };

  inherit
    fieldOrder
    normalizeRepo
    normalizeRepos
    validateRepo
    validateRepos
    isReadmeVisible
    readmeFacingRepos
    ;

  machineReadableRepos = repos: normalizeRepos repos;
  featuredRepos = repos: readmeFacingRepos repos;
  recentRepos = repos: readmeFacingRepos repos;
}
