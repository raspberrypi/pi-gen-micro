import subprocess
from os import listdir, path, mkdir, stat, chmod
import stat as permissions
import shutil

class addon:
    def __init__(self, type, path):
        self.type = type
        self.path = path 
    def __str__(self):
        return f"{self.type}: {self.path}"

# class component:
#     def __init__(self, name: str, enabled: bool):
#         self.name = name
#         self.enabled = enabled 
#     def __str__(self):
#         return f"{self.name}: {str(self.enabled)}"

class configuration:
    def __init__(self, name, addons, params, components={}):
        self.addons = addons
        self.params = params
        self.name = name
        self.num_to_params = {}
        self.components_descriptor = get_default_components()
        self.components = components
        if components == {}:
            for component in self.components_descriptor:
                self.components.update({component: False})

        for num, param in zip(range(len(self.params)), self.params):
            if param != "":
                self.num_to_params.update({num: param})
        
    def __str__(self):
        return str(self.name)
    def pprint(self):
        ret_str = "Configuration class for: " + self.name
        ret_str += "\nHas parameters:\n"
        for param in self.params:
            ret_str += param + ": " + self.params[param] + "\n"
        ret_str += "\nHas Addons:\n"
        for addon in self.addons:
            ret_str += addon.type + ": " + addon.path + "\n"
        ret_str += "\nHas Components:\n"
        for comp in self.components:
            ret_str += comp + ": " + str(self.components[comp]) + "\n"
        return ret_str

    def write_params(self):
        f = open(get_configuration_root() + str(self.name) + "/build.parameters", "w")
        for parameter in self.params:
            f.write(parameter + "=" + self.params[parameter] + "\n")
        f.close()  
  
    def write_addons(self):
        f = open(get_configuration_root() + str(self.name) + "/build.addons", "w")
        for addon in self.addons:
            f.write(addon.type + ": " + addon.path + "\n")
        f.close()

    def write_components(self):
        f = open(get_configuration_root() + str(self.name) + "/build.components", "w+")
        for comp in self.components:
            if self.components[comp]:
                f.write(comp + "\n")
        f.close()

    def write_build_files(self):
        packages_file = open(get_configuration_root() + str(self.name) + "/packages.list", "w+")
        installer_scripts_file = open(get_configuration_root() + str(self.name) + "/installer_scripts.list", "w+")
        for addon in self.addons:
            if addon.type == "DEBIAN":
                packages_file.write(addon.path + "\n")
            if addon.type == "SCRIPT":
                installer_scripts_file.write("./" + addon.path + "\n")
        packages_file.close()
        installer_scripts_file.close()
        # Enable or disable components
        packages_file = open(get_configuration_root() + str(self.name) + "/components.parameters", "w+")
        for component in self.components:
            if self.components[component]:
                packages_file.write(str(component) + "=1\n")
            else:
                packages_file.write(str(component) + "=0\n")
        packages_file.close()
        
        st = stat(get_configuration_root() + str(self.name) + "/installer_scripts.list")
        chmod(get_configuration_root() + str(self.name) + "/installer_scripts.list", st.st_mode | permissions.S_IEXEC)

    def remove_components(self):
        for addon in self.addons:
            if "COMPONENT" in addon.type:
                self.addons.remove(addon)

def parse_addon_str(input_str: str) -> addon:
    type = input_str.split(": ")[0]
    path = input_str.split(": ")[1]
    return addon(type, path)

def parse_addons_file(path):
    f = open(path, "r")
    contents = f.read()
    addons_list = []
    for addon in contents.split("\n"):
        if addon != "":
            addons_list.append(parse_addon_str(addon))
    return addons_list

def parse_params_file(path):
    f = open(path, "r")
    contents = f.read()
    build_parameters = {}
    num_to_param = {}
    for num, paramline in zip(range(len(contents.split("\n"))), contents.split("\n")):
        if paramline != "":
            build_parameters.update({paramline.split("=")[0]: paramline.split("=")[1]})
    return build_parameters

def parse_components_file(path):
    f = open(path, "r")
    contents = f.read()
    active_components = []
    for compline in contents.split("\n"):
        if compline != "":
            active_components.append(compline)
    return active_components

def make_new_configuration(name):
    mkdir(get_configuration_root() + name)
    shutil.copyfile("default.parameters", get_configuration_root() + name + "/build.parameters")
    shutil.copyfile("default.addons", get_configuration_root() + name + "/build.addons")
    shutil.copyfile("default.components", get_configuration_root() + name + "/build.components")

def list_configurations():
    configurations = listdir(get_configuration_root())
    ret = []
    for directory in configurations:
        addons = parse_addons_file(get_configuration_root() + directory + "/build.addons")
        build_parameters = parse_params_file(get_configuration_root() + directory + "/build.parameters")
        ret.append(configuration(directory, addons, build_parameters))
    return ret


def get_configuration(name):
    addons = parse_addons_file(get_configuration_root() + name + "/build.addons")
    build_parameters = parse_params_file(get_configuration_root() + name + "/build.parameters")
    availible_components = get_default_components()
    components = {}
    active_components = parse_components_file(get_configuration_root() + name + "/build.components")
    for availible_component in availible_components:
        components.update({availible_component: False})
    for active_component in active_components:
        components.update({active_component: True})
    return configuration(name, addons, build_parameters, components)

def write_params(config_to_use, build_parameters):
    f = open(get_configuration_root() + str(config_to_use) + "/build.parameters", "w")
    for parameter in build_parameters:
        f.write(parameter + "=" + build_parameters[parameter] + "\n")
    f.close()


def get_default_components():
    f = open("supported.components", "r")
    components = {}
    for line in f.read().split("\n"):
        if line != "":
            components.update({line.split(":")[0]: line.split(":")[1]})
    return components

def get_configuration_root():
    f = open("../config", "r")
    content_by_line = f.read().split("\n")
    for line in content_by_line:
        if "CONFIGURATION_ROOT=" in line:
            cfg_root = line.replace("CONFIGURATION_ROOT=", "")
            if cfg_root[-1] != "/":
                cfg_root += "/"
            return cfg_root