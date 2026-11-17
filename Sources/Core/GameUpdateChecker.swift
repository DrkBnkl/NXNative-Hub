import Foundation

// MARK: - Central evaluation of nxnative game updates & recompilation needs

struct RepoState {
    let repoPath: String
    let headCommit: String
    let headSubject: String
    let shaderChain: String?
}

enum GameUpdateChecker {
    /// File names in dm/games/<titleId> that directly influence shaders and their compilation.
    static let shaderRelatedFiles: Set<String> = [
        "shader_map.tsv",
        "shader_pairs.tsv",
        "c1_full.tsv",
        "cb_extent.tsv",
        "pso_manifest.tsv",
        "pso_pairs.tsv",
        "shader_facts.tsv",
        "shader_seen.tsv",
        "shader_map.tsv.conflicts.tsv"
    ]

    /// Loads the current nxnative repository state (HEAD commit and shader chain version).
    static func loadRepoState() -> RepoState? {
        let repo = NXPaths.repoPath
        guard !repo.isEmpty, FileManager.default.fileExists(atPath: repo) else { return nil }
        let gitDir = (repo as NSString).appendingPathComponent(".git")
        guard FileManager.default.fileExists(atPath: gitDir) else { return nil }

        let head = CommandRunner.git(repo, "rev-parse", "--short", "HEAD").trimmedOutput
        guard !head.isEmpty else { return nil }
        let subject = CommandRunner.git(repo, "log", "-1", "--pretty=format:%s").trimmedOutput

        var chain: String?
        let chainHeaderPath = (repo as NSString).appendingPathComponent("dm/gfx/nvn/dmsh_chain.h")
        if let content = try? String(contentsOfFile: chainHeaderPath, encoding: .utf8) {
            if let match = content.range(of: #"DMSH_CHAIN\s+"([0-9a-fA-F]+)""#, options: .regularExpression) {
                let matchedStr = String(content[match])
                if let quote1 = matchedStr.firstIndex(of: "\""),
                   let quote2 = matchedStr.lastIndex(of: "\""),
                   quote1 < quote2 {
                    let start = matchedStr.index(after: quote1)
                    chain = String(matchedStr[start..<quote2])
                }
            }
        }

        return RepoState(repoPath: repo, headCommit: head, headSubject: subject, shaderChain: chain)
    }

    /// Evaluates whether an update exists for the specified game and whether recompilation of shaders
    /// is truly necessary or if an App Update is sufficient.
    static func evaluate(
        titleId: String,
        buildCommit: String?,
        shaderChain: String?,
        mtime: Date,
        repoState: RepoState?
    ) -> GameUpdateStatus {
        guard let repo = repoState else {
            return .unknown(reason: tr("nxnative-Repository nicht gefunden", "nxnative repository not found"))
        }

        // 1. Check if the game's shader chain differs from the repo's current DMSH_CHAIN
        let chainMismatch = (shaderChain != nil && repo.shaderChain != nil && shaderChain != repo.shaderChain)

        // 2. Check profile changes in dm/games/<titleId>
        var profileCommits: [String] = []
        var changedShaderFiles: [String] = []
        let candidateTids = [titleId, SwitchTitleID.baseID(of: titleId)].compactMap { $0 }
        var profileRelPath: String?

        for tid in candidateTids {
            let rel = "dm/games/\(tid)"
            let full = (repo.repoPath as NSString).appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: full) {
                profileRelPath = rel
                break
            }
        }

        if let relPath = profileRelPath {
            let logResult: CommandRunner.Result
            let diffResult: CommandRunner.Result

            if let commit = buildCommit, !commit.isEmpty {
                let verify = CommandRunner.git(repo.repoPath, "rev-parse", "--verify", "\(commit)^{commit}")
                if verify.succeeded {
                    logResult = CommandRunner.git(repo.repoPath, "log", "\(commit)..HEAD", "--oneline", "--", relPath)
                    diffResult = CommandRunner.git(repo.repoPath, "diff", "--name-only", "\(commit)..HEAD", "--", relPath)
                } else {
                    let epoch = Int(mtime.timeIntervalSince1970)
                    logResult = CommandRunner.git(repo.repoPath, "log", "--since=\(epoch)", "--oneline", "--", relPath)
                    diffResult = CommandRunner.git(repo.repoPath, "diff", "--name-only", "--since=\(epoch)", "HEAD", "--", relPath)
                }
            } else {
                let epoch = Int(mtime.timeIntervalSince1970)
                logResult = CommandRunner.git(repo.repoPath, "log", "--since=\(epoch)", "--oneline", "--", relPath)
                diffResult = CommandRunner.git(repo.repoPath, "diff", "--name-only", "--since=\(epoch)", "HEAD", "--", relPath)
            }

            if logResult.succeeded {
                profileCommits = logResult.output
                    .split(separator: "\n")
                    .map(String.init)
                    .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            }

            if diffResult.succeeded {
                let changedPaths = diffResult.output
                    .split(separator: "\n")
                    .map(String.init)
                for path in changedPaths {
                    let filename = (path as NSString).lastPathComponent
                    if shaderRelatedFiles.contains(filename) && !changedShaderFiles.contains(filename) {
                        changedShaderFiles.append(filename)
                    }
                }
            }
        }

        // 3. Check general engine commits
        var engineCommitsCount = 0
        if let commit = buildCommit, !commit.isEmpty {
            let verify = CommandRunner.git(repo.repoPath, "rev-parse", "--verify", "\(commit)^{commit}")
            if verify.succeeded {
                let countResult = CommandRunner.git(repo.repoPath, "rev-list", "--count", "\(commit)..HEAD")
                engineCommitsCount = Int(countResult.trimmedOutput) ?? 0
            } else {
                let epoch = Int(mtime.timeIntervalSince1970)
                let countResult = CommandRunner.git(repo.repoPath, "rev-list", "--since=\(epoch)", "--count", "HEAD")
                engineCommitsCount = Int(countResult.trimmedOutput) ?? 0
            }
        } else {
            let epoch = Int(mtime.timeIntervalSince1970)
            let countResult = CommandRunner.git(repo.repoPath, "rev-list", "--since=\(epoch)", "--count", "HEAD")
            engineCommitsCount = Int(countResult.trimmedOutput) ?? 0
        }

        let hasProfileShaderUpdates = !changedShaderFiles.isEmpty
        let hasProfileUpdates = !profileCommits.isEmpty
        let hasProfileNonShaderUpdates = hasProfileUpdates && !hasProfileShaderUpdates

        // 4. Decision: Shaders need recompilation ONLY if the shader chain or shader definitions changed.
        //    Otherwise, if shaders are unaffected, an App Update is completely sufficient.
        if chainMismatch && (hasProfileShaderUpdates || hasProfileUpdates) {
            return .recompileRecommended(reason: .chainAndProfileUpdated(
                commitsCount: profileCommits.count,
                commitTitles: profileCommits,
                currentChain: shaderChain ?? "?",
                repoChain: repo.shaderChain ?? "?"
            ))
        } else if chainMismatch {
            return .recompileRecommended(reason: .shaderChainUpdated(
                currentChain: shaderChain ?? "?",
                repoChain: repo.shaderChain ?? "?"
            ))
        } else if hasProfileShaderUpdates {
            return .recompileRecommended(reason: .shaderProfileUpdated(
                commitsCount: profileCommits.count,
                commitTitles: profileCommits,
                changedFiles: changedShaderFiles
            ))
        } else if buildCommit == nil && engineCommitsCount > 0 {
            // Older build before commit tracking: shaders could be from any older chain
            return .recompileRecommended(reason: .legacyBuild(
                reason: tr("Älterer Build vor Commit-Tracking", "Older build before commit tracking")
            ))
        } else if hasProfileNonShaderUpdates && engineCommitsCount > 0 {
            // Both engine and non-shader profile updates (e.g. settings/README): App Update suffices
            return .appUpdateAvailable(reason: .engineAndProfile(
                commitsCount: engineCommitsCount,
                commitTitles: profileCommits
            ))
        } else if hasProfileNonShaderUpdates {
            // Non-shader profile changes only: App Update suffices
            return .appUpdateAvailable(reason: .profileNonShader(
                commitsCount: profileCommits.count,
                commitTitles: profileCommits
            ))
        } else if engineCommitsCount > 0 {
            // Engine commits only: App Update suffices
            return .appUpdateAvailable(reason: .engineOnly(commitsCount: engineCommitsCount))
        } else {
            return .upToDate
        }
    }
}
