/// Upgrades older `project.json` files (PRD §5.3, FR-17.5). Add a case per schema bump.
public enum ProjectMigrator {
    public static func migrate(_ project: Project) throws -> Project {
        guard project.schemaVersion <= Project.currentSchemaVersion else {
            throw ProjectStoreError.unsupportedSchema(found: project.schemaVersion, supported: Project.currentSchemaVersion)
        }
        var p = project
        // v1 is the first schema; future steps go here, e.g. `if p.schemaVersion == 1 { …; p.schemaVersion = 2 }`.
        p.schemaVersion = Project.currentSchemaVersion
        return p
    }
}
