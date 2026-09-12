import Darwin
import Foundation

enum ClaudeRecoveryProcess {
    static func run(
        executable: URL, homeDirectory: URL, timeout: TimeInterval = 25,
        shouldContinue: () -> Bool = { true }, recovered: () -> Bool
    ) -> Bool {
        run(
            executable: executable, homeDirectory: homeDirectory, timeout: timeout,
            arguments: ["--safe-mode"], environment: ProcessInfo.processInfo.environment,
            shouldContinue: shouldContinue, recovered: recovered
        )
    }

    static func run(
        executable: URL, homeDirectory: URL, timeout: TimeInterval,
        arguments: [String], environment: [String: String],
        shouldContinue: () -> Bool = { true }, recovered: () -> Bool
    ) -> Bool {
        guard timeout.isFinite, timeout > 0 else { return false }
        var master: Int32 = -1
        var slave: Int32 = -1
        guard openpty(&master, &slave, nil, nil, nil) == 0 else { return false }
        defer {
            close(master)
            if slave >= 0 { close(slave) }
        }
        guard fcntl(master, F_SETFL, O_NONBLOCK) == 0 else { return false }
        var actions: posix_spawn_file_actions_t?
        var attributes: posix_spawnattr_t?
        guard posix_spawn_file_actions_init(&actions) == 0 else { return false }
        defer { posix_spawn_file_actions_destroy(&actions) }
        guard posix_spawnattr_init(&attributes) == 0 else { return false }
        defer { posix_spawnattr_destroy(&attributes) }
        guard posix_spawnattr_setpgroup(&attributes, 0) == 0,
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT)) == 0,
            posix_spawn_file_actions_addchdir_np(&actions, homeDirectory.path) == 0,
            posix_spawn_file_actions_addclose(&actions, master) == 0
        else { return false }
        for descriptor in [STDIN_FILENO, STDOUT_FILENO, STDERR_FILENO] {
            guard posix_spawn_file_actions_adddup2(&actions, slave, descriptor) == 0 else { return false }
        }
        guard posix_spawn_file_actions_addclose(&actions, slave) == 0 else { return false }
        let argv = ([executable.path] + arguments).map { strdup($0) } + [nil]
        let envp =
            cleanEnvironment(executable: executable, homeDirectory: homeDirectory, inherited: environment)
            .map { strdup("\($0.key)=\($0.value)") } + [nil]
        defer {
            argv.forEach { free($0) }
            envp.forEach { free($0) }
        }
        guard shouldContinue() else { return false }
        var pid: pid_t = 0
        let result = argv.withUnsafeBufferPointer { args in
            envp.withUnsafeBufferPointer { env in
                posix_spawn(&pid, executable.path, &actions, &attributes, args.baseAddress!, env.baseAddress!)
            }
        }
        guard result == 0 else { return false }
        close(slave)
        slave = -1
        defer { stop(pid) }
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var nextCheck = ProcessInfo.processInfo.systemUptime
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while ProcessInfo.processInfo.systemUptime < deadline {
            guard shouldContinue(), isRunning(pid) else { return false }
            let now = ProcessInfo.processInfo.systemUptime
            if now >= nextCheck {
                if recovered() { return shouldContinue() && isRunning(pid) }
                nextCheck = now + 2
            }
            var descriptor = pollfd(fd: master, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 50)
            if ready < 0, errno != EINTR { return false }
            if ready > 0, Darwin.read(master, &buffer, buffer.count) <= 0 { usleep(50_000) }
        }
        return false
    }

    private static func cleanEnvironment(
        executable: URL, homeDirectory: URL, inherited: [String: String]
    ) -> [String: String] {
        var result = inherited.filter { ["USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL"].contains($0.key) }
        result["HOME"] = homeDirectory.path
        result["TERM"] = "xterm-256color"
        result["LANG"] = result["LANG"] ?? "en_US.UTF-8"
        result["PATH"] = [
            executable.deletingLastPathComponent().path, homeDirectory.appending(path: ".local/bin").path,
            "/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin", "/usr/sbin", "/sbin",
        ].joined(separator: ":")
        return result
    }

    private static func isRunning(_ pid: pid_t) -> Bool {
        var info = siginfo_t()
        var result: Int32
        repeat {
            result = waitid(P_PID, id_t(pid), &info, WEXITED | WNOHANG | WNOWAIT)
        } while result < 0 && errno == EINTR
        return result == 0 && info.si_pid == 0
    }

    private static func stop(_ pid: pid_t) {
        guard pid > 0 else { return }
        kill(-pid, SIGTERM)
        usleep(100_000)
        kill(-pid, SIGKILL)
        var code: Int32 = 0
        while waitpid(pid, &code, 0) < 0, errno == EINTR {}
    }
}
