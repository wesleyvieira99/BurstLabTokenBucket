#!/usr/bin/env python3
"""Atualiza os downloads do portal usando os fontes em project/; só biblioteca padrão."""
from __future__ import annotations

import argparse
import io
import json
import os
from pathlib import Path
import stat
import zipfile

REPOSITORY = Path(__file__).resolve().parents[1]
# Exclui somente nomes/categorias conhecidos; arquivos-fonte continuam legíveis.
EXCLUDED_DIRECTORIES = frozenset({
    ".git", ".terraform", "target", "node_modules", "__pycache__",
    ".venv", "venv", ".pytest_cache", ".mypy_cache", ".ruff_cache",
    ".aws", ".ssh", ".codex", ".agents", ".openai", ".idea", ".vscode",
    "secrets", ".secrets", "results", "logs",
})
EXCLUDED_NAMES = frozenset({
    ".DS_Store", "Thumbs.db", "credentials", "credentials.json",
    ".credentials", "secrets.json", "secrets.yaml", "secrets.yml",
    "crash.log", "crash.json", "id_rsa", "id_ed25519",
})
EXCLUDED_SUFFIXES = frozenset({
    ".pyc", ".pyo", ".class", ".jar", ".war", ".zip", ".log",
    ".pem", ".key", ".p12", ".pfx", ".jks", ".keystore",
    ".so", ".dll", ".dylib",
})
REQUIRED_FILES = frozenset({
    "README.md", "pom.xml", "Dockerfile", "compose.yaml",
    "common/pom.xml", "service-a/pom.xml", "service-b/pom.xml", "worker/pom.xml",
    "common/src/main/resources/lua/admit-v1.lua", "infra/versions.tf",
    "infra/.terraform.lock.hcl", "infra/terraform.tfvars.example",
})


def excluded(path: Path) -> bool:
    """Filtra caminhos relativos sem esconder exemplos de configuração sem segredo."""
    if any(part in EXCLUDED_DIRECTORIES for part in path.parts):
        return True
    name = path.name
    if name in EXCLUDED_NAMES or path.suffix.lower() in EXCLUDED_SUFFIXES:
        return True
    if name == ".env" or (name.startswith(".env.") and not name.endswith((".example", ".sample"))):
        return True
    if ".tfstate" in name or ".tfplan" in name:
        return True
    if name.endswith((".tfvars", ".tfvars.json")):
        return True
    return name.startswith(".terraform.tfstate.lock")


def collect_files(project: Path) -> list[tuple[str, bytes, int]]:
    """Lê apenas arquivos UTF-8 regulares; nunca segue links para fora do projeto."""
    collected = []
    for folder, directories, filenames in os.walk(project, followlinks=False):
        current = Path(folder)
        kept = []
        for name in sorted(directories):
            directory = current / name
            if excluded(directory.relative_to(project)):
                continue
            if directory.is_symlink():
                raise ValueError(f"Diretório simbólico não permitido: {directory.relative_to(project)}")
            kept.append(name)
        directories[:] = kept
        for name in sorted(filenames):
            source = current / name
            relative = source.relative_to(project)
            if excluded(relative):
                continue
            if source.is_symlink() or not source.is_file():
                raise ValueError(f"Arquivo não regular: {relative}")
            data = source.read_bytes()
            if b"\0" in data:
                raise ValueError(f"Binário inesperado no projeto: {relative}")
            try:
                data.decode("utf-8")
            except UnicodeDecodeError as error:
                raise ValueError(f"Arquivo precisa estar em UTF-8: {relative}") from error
            mode = 0o755 if source.stat().st_mode & stat.S_IXUSR else 0o644
            collected.append((relative.as_posix(), data, mode))
    collected.sort(key=lambda item: item[0])
    missing = REQUIRED_FILES - {item[0] for item in collected}
    if missing:
        raise ValueError("Fontes essenciais ausentes: " + ", ".join(sorted(missing)))
    return collected


def archive_bytes(files: list[tuple[str, bytes, int]]) -> bytes:
    """Ordem, data e permissões explícitas evitam diferenças causadas pelo horário."""
    output = io.BytesIO()
    with zipfile.ZipFile(output, "w", compression=zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for relative, data, mode in files:
            info = zipfile.ZipInfo("burstlab-project/" + relative, date_time=(1980, 1, 1, 0, 0, 0))
            info.create_system = 3
            info.external_attr = (stat.S_IFREG | mode) << 16
            info.compress_type = zipfile.ZIP_DEFLATED
            archive.writestr(info, data, compress_type=zipfile.ZIP_DEFLATED, compresslevel=9)
    return output.getvalue()


def build(project: Path, destination: Path) -> int:
    project = project.resolve()
    destination = destination.resolve()
    if not project.is_dir():
        raise ValueError(f"Pasta do projeto não encontrada: {project}")
    if destination == project or project in destination.parents:
        raise ValueError("A saída não pode ficar dentro de project/.")
    files = collect_files(project)
    listing = [{"path": relative, "content": data.decode("utf-8")} for relative, data, _ in files]
    encoded = (json.dumps(listing, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
    zipped = archive_bytes(files)
    # Confirma que JSON e ZIP têm exatamente os mesmos arquivos e conteúdos.
    with zipfile.ZipFile(io.BytesIO(zipped)) as archive:
        if archive.testzip() is not None:
            raise ValueError("ZIP inválido")
        if len(archive.namelist()) != len(listing):
            raise ValueError("Quantidade de arquivos divergente")
        for item in listing:
            if archive.read("burstlab-project/" + item["path"]).decode("utf-8") != item["content"]:
                raise ValueError("Conteúdo divergente: " + item["path"])
    destination.mkdir(parents=True, exist_ok=True)
    (destination / "files.json").write_bytes(encoded)
    (destination / "burstlab-projeto.zip").write_bytes(zipped)
    (destination / ".nojekyll").write_text("", encoding="utf-8")
    print(f"Portal atualizado: {len(files)} arquivos; ZIP {len(zipped):,} bytes; saída {destination}")
    return len(files)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=REPOSITORY / "portal" / "dist",
                        help="Destino dos três arquivos gerados (padrão: portal/dist).")
    args = parser.parse_args()
    try:
        build(REPOSITORY / "project", args.output_dir)
    except (OSError, ValueError) as error:
        parser.exit(1, f"Falha ao preparar o portal: {error}\n")


if __name__ == "__main__":
    main()
