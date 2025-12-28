- Sanitize the fetch account & fetch repository queries by handle to prevent any query injection vulnerability
- Does SourceHut have issues?
- How does the mailing list work in SourceHut
- We need to implement authentication
- Decide how storage can be scaled horizontally (e.g. can we use Ceph in Elixir).
  - What about SQLite vs Postgres vs MySQL
- Can we include the marketing pages here and remove them at compile-time?
  - Or maybe have something like GitHub pages, and make those pages a github-pages kind of site that's deployed to Micelio?
- I think we should have a zig CLI as part of this repo that can serve as an interface to the repository
- Support OAuth2 dynamic registration such that MCP clients can interface with it.
- Set up OpenAPISpex
- What should be the blocks of a repo (issues, mrs, settings) and the routes
  - Do we want issues?
  
- Fediverse integration
- Rate limiting when not authenticated
- Public vs private repositories
- OAuth2 workflow for the CLI
- Continuous integration that can run locally
- OpenGraph images for repositories

- Does it make sense to keep track of file-system or git operations per account/repo so that we can make decisions around sharding.
- What about PR stacking which GH is working on? Should we bring that concept?
- Figure out how to establish the boundaries in the project using Boundary
- Add support for declaring as admin of the instance and authorize the access

- If we implement something like GitHub pages, do we need to use branches to deploy a static site?
- Can we store issues or prs in the repository itself to make it more portable?
- What about a desktop app? Can we build it with Zig, like Zed is doing with Rust? Or at least build the core in Zig, and do platform-specific UI.
## Project ideas
- Kamal but without dependency on Ruby, just pure Zig
- Something like Kamal, but for static sites. Or maybe extend Kamal to support that?
