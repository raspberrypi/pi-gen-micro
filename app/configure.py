from textual.app import App, ComposeResult
from textual.containers import ScrollableContainer, Container
from textual.widgets import Header, Footer, DataTable, Static, Button, Label, Input, TextArea, SelectionList
from textual.widgets.selection_list import Selection
from textual.reactive import reactive
from textual.message import Message
from textual.screen import Screen
from textual.widget import Widget
from textual.geometry import Size
from textual import on
from textual import events
import numpy as np
import build_helper
from os import listdir, path, mkdir, stat, chmod
import stat as permissions

ADDON_TABLE = [
    ("Additional Components",),
]
PARAMETER_TABLE = [
    ("PARAMETER", "ENTRY"),
]
CONFIGURATIONS = [
    ("Configuration Name", ),
]

build_parameters = {}
num_to_param = {}
addons_list = []

class InstallList(Widget):
    addons = reactive(addons_list.copy())
    components = reactive({})
    def compose(self) -> ComposeResult:
        yield DataTable(id="addons_table")
        yield(Container(Button(id="delete_addon", label="Delete Selected Addon", classes="build_button"), Button(id="edit_addon", label="Edit Selected Addon", classes="build_button"), classes="horizontal_layout"))
    def __init__(self, config_to_use: build_helper.configuration):
        self.config = config_to_use
        super().__init__()
    def update_addons(self) -> None:
        self.addons = self.config.addons.copy()
        self.components = self.config.components.copy()
    def watch_addons(self, params) -> None:
        """Called when the devices variable changes"""
        table = self.query_one(DataTable)
        table.clear()

        for addon in self.addons:
            table.add_row(str(addon))
        for component in self.config.components:
            if self.config.components[component]:
                table.add_row("INCLUDE-COMPONENT: " + component)
    def watch_components(self, params) -> None:
        """Called when the devices variable changes"""
        table = self.query_one(DataTable)
        table.clear()

        for addon in self.addons:
            table.add_row(str(addon))
        for component in self.config.components:
            if self.config.components[component]:
                table.add_row("INCLUDE-COMPONENT: " + component)

    def on_mount(self) -> None:
        table = self.query_one(DataTable)
        table.add_columns(*ADDON_TABLE[0])
        table.add_rows(ADDON_TABLE[1:])

        table = self.query_one(DataTable)
        table.clear()

        for addon in self.config.addons:
            table.add_row(str(addon)) 
        for component in self.config.components:
            if self.config.components[component]:
                table.add_row("INCLUDE-COMPONENT: " + component)
        self.set_interval(1/20, self.update_addons)

class ParametersList(Widget):
    params = reactive(build_parameters.copy())
    def compose(self) -> ComposeResult:
        yield DataTable(id="param_table")
    def __init__(self, config_to_use):
        self.config = config_to_use
        super().__init__()
    def update_params(self) -> None:
        self.params = self.config.params.copy()
    def watch_params(self, params) -> None:
        """Called when the devices variable changes"""
        table = self.query_one(DataTable)
        table_devices = []
        table.clear()
        for build_parameter in self.config.params:
            table.add_row(build_parameter, self.config.params[build_parameter])

    def on_mount(self) -> None:
        table = self.query_one(DataTable)
        table.add_columns(*PARAMETER_TABLE[0])
        table.add_rows(PARAMETER_TABLE[1:])
        table = self.query_one(DataTable)
        table_devices = []
        table.clear()
        for build_parameter in self.config.params:
            table.add_row(build_parameter, self.config.params[build_parameter]) 
        self.set_interval(1/20, self.update_params)

class Configuration(Label):
    def compose(self) -> ComposeResult:
         yield Label("Building for - - - - - ", classes="Configuration")
    def __init__(self):
        super().__init__()

class MainScreen(Screen):
    def __init__(self, config: build_helper.configuration):
        self.config = config
        super().__init__()
    def compose(self) -> ComposeResult:
            """Create child widgets for the app."""
            f = open("pi-gen-micro.txt", "r")
            yield Static(f.read())
            f.close()
            yield(Container(InstallList(self.config), ParametersList(self.config), classes="horizontal_layout"))
            yield(Container(Button("Manually Install Packages", id="manual_build_button", classes="build_button"), Button("Add or remove components", id="component_selection_button", classes="build_button"), Button("Add .deb files", id="add_dpkg_button", classes="build_button"), Button("Save", id="build_button", classes="build_button"), classes="build_container"))
            yield Footer()

class EditComponentsScreen(Screen):
    def __init__(self, config: build_helper.configuration):
        self.config = config
        super().__init__()
    def compose(self) -> ComposeResult:
            """Create child widgets for the app."""
            f = open("pi-gen-micro.txt", "r")
            yield Static(f.read())
            f.close()
            selectionlist = []
            for component in self.config.components:
                selectionlist.append(Selection(component, component, self.config.components[component]))
            yield SelectionList[str](*selectionlist)
            yield Button("Save Components List", id="save_components_list", classes="build_button")
            yield Footer()

class ManualInstallScreen(Screen):
    def __init__(self, config: build_helper.configuration, value=""):
        self.config = config
        if value != "":
            # Means that we want to open an already existing script
            self.path = value
            f = open(build_helper.get_configuration_root() + str(self.config) + "/" + value, "r")
            self.code = f.read() 
            f.close()
        else:
            self.path = ""
            self.code = ""
        super().__init__()
    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        f = open("pi-gen-micro.txt", "r")
        yield Static(f.read())
        f.close()
        yield Input(self.path, placeholder="Install Script Name")
        yield TextArea.code_editor(self.code, language="bash", id="code_area")
        yield Container(Button("Save", id="save_script"), Button(id="exit_screen", label="Cancel"), classes="horizontal_layout")
        yield Footer()

    @on(Button.Pressed)
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "save_script":
            code = self.query_one(TextArea)
            input = self.query_one(Input)
            # Write the script to the file
            f = open(build_helper.get_configuration_root() + str(self.config) + "/" + input.value, "w+")
            f.write(code.text)
            f.close()
            st = stat(build_helper.get_configuration_root() + str(self.config) + "/" + input.value)
            chmod(build_helper.get_configuration_root() + str(self.config) + "/" + input.value, st.st_mode | permissions.S_IEXEC)
            self.config.addons.append(build_helper.addon(type="SCRIPT", path=input.value))
        if event.button.id == "exit_screen" and self.path != "":
            # Need to restore the deleted addon (file still exists)
            self.config.addons.append(build_helper.addon(type="SCRIPT", path=self.path))

class DPGKInstallScreen(Screen):
    def __init__(self, config: build_helper.configuration, value=""):
        self.config = config
        self.value = value
        super().__init__()
    def compose(self) -> ComposeResult:
        """Create child widgets for the app."""
        yield Container(Static("Include a .deb/.udeb file in the image\n"), Input(placeholder="/path/to/.deb/file", value=self.value, id="debian_path_input"), Container(Button("Add", id="add_debian_package", classes="build_button"), Button(id="exit_screen", label="Cancel", classes="build_button"), classes="horizontal_layout"), id="dialog")
    
    @on(Button.Pressed)
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if event.button.id == "add_debian_package":
            input = self.query_one("#debian_path_input")
            self.config.addons.append(build_helper.addon(type="DEBIAN", path=input.value))
        if event.button.id == "exit_screen" and self.value != "":
            # Restore deleted addon
            self.config.addons.append(build_helper.addon(type="DEBIAN", path=self.value))

class EditParamScreen(Screen):
    def __init__(self, paramname, currentvalue):
        self.paramname = paramname
        self.currentvalue = currentvalue
        super().__init__()

    def compose(self) -> ComposeResult:
        yield Container(Static(self.paramname + "\n"), Input(value=self.currentvalue, id="input_param_"+ self.paramname), Container(Button("Save", id="save_param_"+self.paramname), Button(id="exit_screen", label="Cancel"), classes="horizontal_layout"), id="dialog")

class TerminaltoosmallScreen(Screen):
    def compose(self) -> ComposeResult:
        yield Static("Terminal screen too small, please set to at least 25 rows, 110 cols.")



class GreeterScreen(Screen):
    def __init__(self):
        super().__init__()

    def compose(self) -> ComposeResult:
        f = open("pi-gen-micro.txt", "r")
        yield Static(f.read(), id="pi-gen-micro")
        f.close()
        yield(DataTable(id="configuration_table"))
        yield(Container(Button("Make New Configuration", id="new_configuration"), classes="build_container"))
        yield Footer()
    def on_mount(self) -> None:
        table = self.query_one(DataTable)
        table.add_columns(*CONFIGURATIONS[0])
        table.add_rows(CONFIGURATIONS[1:])

        table = self.query_one(DataTable)
        table.clear()
        for configuration in configurations:
            table.add_row(str(configuration)) 

class App(App):
    CSS_PATH = "build.css"
    BINDINGS = [("m", "mainscreen", "Main Screen"), ("q", "quit", "Quit")]
    SCREENS = {"MainScreen": MainScreen(""), "ManualInstallScreen": ManualInstallScreen(""), "GreeterScreen": GreeterScreen()}

    def on_mount(self) -> None:
        self.title = "pi-gen-micro"
        self.push_screen(GreeterScreen())
        self.selected_addon_coord = 0


    def action_mainscreen(self):
        self.pop_screen()
        self.push_screen(MainScreen(self.config_to_use))
    
    @on(DataTable.CellSelected)
    def on_cell_selected(self, event: DataTable.CellSelected) -> None:  
        #event.coordinate[1]
        if event.data_table.id == "param_table":
            self.push_screen(EditParamScreen(paramname=self.config_to_use.num_to_params[event.coordinate[0]], currentvalue=self.config_to_use.params[self.config_to_use.num_to_params[event.coordinate[0]]]))
        if event.data_table.id == "configuration_table":
            self.config_to_use = build_helper.get_configuration(event.value)
            self.push_screen(MainScreen(self.config_to_use))
        if event.data_table.id == "addons_table":
            self.selected_addon_coord = event.coordinate[0]
    
    @on(Button.Pressed)
    def on_button_pressed(self, event: Button.Pressed) -> None:
        if "save_param_" in event.button.id:
            paramname = event.button.id.replace("save_param_", "")
            if paramname == "New_Build_Configuration_Name":
                input = self.query_one("#input_param_" + paramname)
                new_build_name = input.value
                build_helper.make_new_configuration(new_build_name)
                self.config_to_use = build_helper.get_configuration(new_build_name)
                self.pop_screen()
                self.push_screen(MainScreen(self.config_to_use))
            else:
                input = self.query_one("#input_param_" + paramname)
                self.config_to_use.params[paramname] = input.value
                self.pop_screen()

        if "build_button" == event.button.id:
            # Save build parameters to a file
            self.config_to_use.write_addons()
            self.config_to_use.write_params()
            self.config_to_use.write_components()
            self.config_to_use.write_build_files()
            quit()

        if "manual_build_button" == event.button.id:
            self.push_screen(ManualInstallScreen(self.config_to_use))
        if "add_dpkg_button" == event.button.id:
            self.push_screen(DPGKInstallScreen(self.config_to_use))
        if "add_debian_package" == event.button.id:
            self.pop_screen()
        if "save_script" == event.button.id:
            self.pop_screen()
        if "new_configuration" == event.button.id:
            self.push_screen(EditParamScreen(paramname="New_Build_Configuration_Name", currentvalue=""))
        if "component_selection_button" == event.button.id:
            self.push_screen(EditComponentsScreen(self.config_to_use))
        if "save_components_list" == event.button.id:
            self.pop_screen()
        if "delete_addon" in event.button.id:
            # Need to remove the specific addon...
            if self.selected_addon_coord >= len(self.config_to_use.addons):
                # Must be a component that we need to remove...
                pass
            else:
                if len(self.config_to_use.addons) != 0:
                    self.config_to_use.addons.pop(self.selected_addon_coord) 
                    self.selected_addon_coord = 0
        if "edit_addon" in event.button.id:
            # Need to remove the specific addon...
            if self.selected_addon_coord >= len(self.config_to_use.addons):
                # Must be a component that we need to edit. There's a screen for that...
                self.push_screen(EditComponentsScreen(self.config_to_use))
            else:
                if len(self.config_to_use.addons) != 0:
                    addon_to_edit = self.config_to_use.addons[self.selected_addon_coord]
                    if addon_to_edit.type == "DEBIAN":
                        self.push_screen(DPGKInstallScreen(self.config_to_use, value=addon_to_edit.path))
                    if addon_to_edit.type == "SCRIPT":
                        self.push_screen(ManualInstallScreen(self.config_to_use, value=addon_to_edit.path))
                    self.config_to_use.addons.pop(self.selected_addon_coord) 
                    self.selected_addon_coord = 0
        if "exit_screen" == event.button.id:
            self.pop_screen()

    def on_resize(self):
        if self.size[0] > 109 and self.size[1] > 25:
            if self.screen.name != None:
                if "TerminaltoosmallScreen" in self.screen.name:
                    self.pop_screen()
        else:
            if self.screen.name != None:
                if "TerminaltoosmallScreen" in self.screen.name:
                    pass
                else:
                    self.push_screen(TerminaltoosmallScreen(name="TerminaltoosmallScreen"))
            else:
                self.push_screen(TerminaltoosmallScreen(name="TerminaltoosmallScreen"))

    @on(SelectionList.SelectedChanged)
    def on_selected_changed(self, event: SelectionList.SelectedChanged):
        selection_list = event.selection_list.selected
        for component in self.config_to_use.components:
            self.config_to_use.components.update({component: False})
        for component in selection_list:
            self.config_to_use.components.update({component: True})

build_parameters = {}
addons_list = []


## Get the configurations list
configurations = build_helper.list_configurations()
config_to_use = ""

if __name__ == "__main__":
    app = App()
    app.run()