local dap_config = {
  name = "Rust tools debug",
  type = "rt_lldb",
  request = "launch",
  program = json.executable,
  args = args.executableArgs or {},
  cwd = args.workspaceRoot,
  stopOnEntry = false,

  -- if you change `runInTerminal` to true, you might need to change the yama/ptrace_scope setting:
  --
  --    echo 0 | sudo tee /proc/sys/kernel/yama/ptrace_scope
  --
  -- Otherwise you might get the following error:
  --
  --    Error on launch: Failed to attach to the target process
  --
  -- But you should be aware of the implications:
  -- https://www.kernel.org/doc/html/latest/admin-guide/LSM/Yama.html
  runInTerminal = false,
}
