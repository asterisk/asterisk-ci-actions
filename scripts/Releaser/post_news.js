#!/usr/bin/env node

const path = require('node:path');
const WPPost = require('wp-post').default;

function parseArgs(argv) {
  const args = {
    file: null,
    apiUrl: null,
    user: null,
    password: null,
    postEndpoint: 'asterisk-news',
  };

  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i];
    const next = argv[i + 1];

    if (arg === '--file') {
      args.file = next;
      i += 1;
    } else if (arg === '--api-url') {
      args.apiUrl = next;
      i += 1;
    } else if (arg === '--user') {
      args.user = next;
      i += 1;
    } else if (arg === '--password') {
      args.password = next;
      i += 1;
    } else if (arg === '--post-endpoint') {
      args.postEndpoint = next;
      i += 1;
    }
  }

  return args;
}

async function main() {
  const args = parseArgs(process.argv.slice(2));

  if (!args.file || !args.apiUrl || !args.user || !args.password) {
    throw new Error('Missing required arguments: --file --api-url --user --password');
  }

  const post = new WPPost(path.resolve(args.file));
  post.checkPost();

  const config = post.getConfig();
  config.apiUrl = args.apiUrl.replace(/\/+$/, '');
  config.authUser = args.user;
  config.authPassword = args.password;
  config.apiPostUrl = args.postEndpoint;

  // Keep compatibility if incoming metadata ever uses the old status value.
  if (post.postData.status === 'published') {
    post.postData.status = 'publish';
  }

  const postId = await post.postAsync(config.apiUrl, config.authUser, config.authPassword);
  console.log(`Published Asterisk news post ${postId}`);
}

main().catch((error) => {
  console.error('HTTP status:', error.response?.status);
  console.error(`WordPress publication failed${error.response ? ` (HTTP ${error.response.status})` : ''}.`);
  process.exitCode = 1;
});
