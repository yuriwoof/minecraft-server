package jp.yuriwoof.minecraft;

import net.kyori.adventure.text.Component;
import org.bukkit.command.Command;
import org.bukkit.command.CommandExecutor;
import org.bukkit.command.CommandSender;
import org.bukkit.command.PluginCommand;
import org.bukkit.plugin.java.JavaPlugin;
import org.jetbrains.annotations.NotNull;

public final class PaperStarterPlugin extends JavaPlugin implements CommandExecutor {
    @Override
    public void onEnable() {
        PluginCommand command = getCommand("paperstarter");
        if (command == null) {
            throw new IllegalStateException("The paperstarter command is missing from plugin.yml");
        }
        command.setExecutor(this);
    }

    @Override
    public boolean onCommand(
            @NotNull CommandSender sender,
            @NotNull Command command,
            @NotNull String label,
            @NotNull String[] args
    ) {
        sender.sendMessage(Component.text("Paper plugin starter is running."));
        return true;
    }
}
