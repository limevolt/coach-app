// Range les cartes du tableau GitHub « Coach App » d'après l'état et les étiquettes
// des issues et pull requests. Lancé par .github/workflows/tableau.yml.
//
// Règles (la première qui s'applique gagne) :
//   pull request ouverte          → À fusionner (brouillon → En cours)
//   pull request fermée/fusionnée → Fait
//   issue fermée ou `obsolète`    → Fait
//   `à retester`                  → À tester par moi
//   `en cours` ou PR ouverte liée → En cours
//   sinon                         → À faire

const TITRE = 'Coach App';
const COL = {
  todo: 'À faire',
  doing: 'En cours',
  test: 'À tester par moi',
  merge: 'À fusionner',
  done: 'Fait',
};

const STATUT = `projectItems(first: 10) { nodes { id project { id }
  fieldValueByName(name: "Status") { ... on ProjectV2ItemFieldSingleSelectValue { optionId } } } }`;
// Champs lus pour une issue et pour une pull request. Une liste d'issues ne peut
// contenir que des issues : on n'y demande que les champs d'issue (et inversement).
// L'état d'une PR est lu sous le nom prState : GitHub refuse deux champs « state »
// de types différents dans la même requête (issue ou PR).
const ISSUE = `__typename id number state labels(first: 20) { nodes { name } }
  closedByPullRequestsReferences(first: 5, includeClosedPrs: false) { nodes { state } }
  ${STATUT}`;
const PR = `__typename id number prState: state isDraft labels(first: 20) { nodes { name } }
  closingIssuesReferences(first: 10) { nodes { number } }
  ${STATUT}`;
const CHAMPS = { issues: ISSUE, pullRequests: PR };
const LES_DEUX = `... on Issue { ${ISSUE} } ... on PullRequest { ${PR} }`;

function colonne(n) {
  const labels = n.labels.nodes.map((l) => l.name.toLowerCase());
  if (n.__typename === 'PullRequest') {
    if (n.prState !== 'OPEN') return 'done';
    return n.isDraft ? 'doing' : 'merge';
  }
  if (n.state === 'CLOSED' || labels.includes('obsolète')) return 'done';
  if (labels.includes('à retester')) return 'test';
  if (labels.includes('en cours')) return 'doing';
  if (n.closedByPullRequestsReferences.nodes.some((p) => p.state === 'OPEN')) return 'doing';
  return 'todo';
}

module.exports = async ({ github, context, core }) => {
  const { owner, repo } = context.repo;

  // 1. Le tableau et sa colonne « Status »
  const q = await github.graphql(
    `query($login: String!) { repositoryOwner(login: $login) {
      ... on User { projectsV2(first: 50) { nodes { id title } } }
      ... on Organization { projectsV2(first: 50) { nodes { id title } } } } }`,
    { login: owner }
  );
  const proj = q.repositoryOwner.projectsV2.nodes.find((p) => p.title === TITRE);
  if (!proj) return core.setFailed(`Tableau « ${TITRE} » introuvable (vérifier le secret PROJECT_TOKEN).`);

  const f = await github.graphql(
    `query($id: ID!) { node(id: $id) { ... on ProjectV2 {
      field(name: "Status") { ... on ProjectV2SingleSelectField { id options { id name } } } } } }`,
    { id: proj.id }
  );
  const status = f.node.field;
  const opt = {};
  for (const [k, nom] of Object.entries(COL)) {
    const o = status.options.find((x) => x.name === nom);
    if (!o) return core.setFailed(`Colonne « ${nom} » introuvable sur le tableau.`);
    opt[k] = o.id;
  }

  // 2. Placer une issue ou une PR dans la bonne colonne
  async function ranger(n) {
    const col = colonne(n);
    let item = n.projectItems.nodes.find((i) => i.project.id === proj.id);
    if (!item) {
      const r = await github.graphql(
        `mutation($p: ID!, $c: ID!) { addProjectV2ItemById(input: { projectId: $p, contentId: $c }) { item { id } } }`,
        { p: proj.id, c: n.id }
      );
      item = { id: r.addProjectV2ItemById.item.id, fieldValueByName: null };
    }
    if (item.fieldValueByName && item.fieldValueByName.optionId === opt[col]) return;
    await github.graphql(
      `mutation($p: ID!, $i: ID!, $f: ID!, $o: String!) { updateProjectV2ItemFieldValue(input: {
        projectId: $p, itemId: $i, fieldId: $f, value: { singleSelectOptionId: $o } }) { projectV2Item { id } } }`,
      { p: proj.id, i: item.id, f: status.id, o: opt[col] }
    );
    core.info(`#${n.number} → ${COL[col]}`);
  }

  async function un(numero) {
    const r = await github.graphql(
      `query($o: String!, $r: String!, $n: Int!) { repository(owner: $o, name: $r) {
        issueOrPullRequest(number: $n) { ${LES_DEUX} } } }`,
      { o: owner, r: repo, n: numero }
    );
    return r.repository.issueOrPullRequest;
  }

  async function liste(champ, filtre, toutes) {
    const res = [];
    let apres = null;
    do {
      const r = await github.graphql(
        `query($o: String!, $r: String!, $a: String) { repository(owner: $o, name: $r) {
          ${champ}(first: 50, after: $a, ${filtre}) { pageInfo { hasNextPage endCursor } nodes { ${CHAMPS[champ]} } } } }`,
        { o: owner, r: repo, a: apres }
      );
      const c = r.repository[champ];
      res.push(...c.nodes);
      apres = toutes && c.pageInfo.hasNextPage ? c.pageInfo.endCursor : null;
    } while (apres);
    return res;
  }

  // 3. Un seul élément (événement) ou tout le tableau (lancement manuel)
  const numero = context.payload.issue?.number ?? context.payload.pull_request?.number;
  if (numero && context.eventName !== 'workflow_dispatch') {
    const n = await un(numero);
    await ranger(n);
    if (n.__typename === 'PullRequest') {
      for (const i of n.closingIssuesReferences.nodes) await ranger(await un(i.number));
    }
    return;
  }

  const recents = 'orderBy: { field: UPDATED_AT, direction: DESC }';
  const tout = [
    ...(await liste('issues', 'states: OPEN', true)),
    ...(await liste('pullRequests', 'states: OPEN', true)),
    ...(await liste('issues', `states: CLOSED, ${recents}`, false)),
    ...(await liste('pullRequests', `states: [CLOSED, MERGED], ${recents}`, false)),
  ];
  for (const n of tout) await ranger(n);
  core.info(`${tout.length} éléments vérifiés.`);
};
