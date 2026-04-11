import React, { useEffect, useState } from "react";
import "./AdminUsers.css";
import { fetchUsersFromFirebase, updateUserRoles } from "./firebaseClient";

interface UserRow {
  username: string;
  twitterUsername?: string | null;
  roles: string[];
  profilePictureUrl?: string;
}

const AdminUsers: React.FC = () => {
  const [users, setUsers] = useState<UserRow[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState("");
  const [savingUsers, setSavingUsers] = useState<Record<string, boolean>>({});

  useEffect(() => {
    const loadUsers = async () => {
      setLoading(true);
      setError("");
      try {
        const list = await fetchUsersFromFirebase();
        setUsers(list as UserRow[]);
      } catch (err) {
        console.error("Failed to load users", err);
        setError("Failed to load users.");
      } finally {
        setLoading(false);
      }
    };

    loadUsers();
  }, []);

  const handleToggle = async (username: string, role: "admin" | "sponsor") => {
    const currentUser = users.find((user) => user.username === username);
    if (!currentUser) return;

    const previousRoles = Array.isArray(currentUser.roles) ? currentUser.roles : [];
    const roleSet = new Set(previousRoles);
    if (roleSet.has(role)) {
      roleSet.delete(role);
    } else {
      roleSet.add(role);
    }
    roleSet.add("player");
    const pendingRoles = Array.from(roleSet);

    setUsers((current) =>
      current.map((user) =>
        user.username === username ? { ...user, roles: pendingRoles } : user
      )
    );

    setSavingUsers((current) => ({ ...current, [username]: true }));
    try {
      const updated = await updateUserRoles(username, pendingRoles);
      if (updated) {
        setUsers((current) =>
          current.map((user) =>
            user.username === username ? { ...user, roles: updated } : user
          )
        );
      }
    } catch (err) {
      console.error("Failed to update roles", err);
      setError("Failed to update roles. Please try again.");
      setUsers((current) =>
        current.map((user) =>
          user.username === username ? { ...user, roles: previousRoles } : user
        )
      );
    } finally {
      setSavingUsers((current) => ({ ...current, [username]: false }));
    }
  };

  if (loading) {
    return (
      <div className="admin-users">
        <div className="admin-users__header">
          <h1>Admin Users</h1>
          <p>Loading users...</p>
        </div>
      </div>
    );
  }

  return (
    <div className="admin-users">
      <div className="admin-users__header">
        <h1>Admin Users</h1>
        <p>Manage roles for platform access.</p>
        {error ? <span className="admin-users__error">{error}</span> : null}
      </div>

      <div className="admin-users__table">
        <div className="admin-users__row admin-users__row--head">
          <span>User</span>
          <span>X Handle</span>
          <span>Player</span>
          <span>Admin</span>
          <span>Sponsor</span>
        </div>

        {users.length === 0 ? (
          <div className="admin-users__empty">No users yet.</div>
        ) : (
          users.map((user) => {
            const roles = user.roles || [];
            const isAdmin = roles.includes("admin");
            const isSponsor = roles.includes("sponsor");
            const isPlayer = roles.includes("player");
            const cleanRowUsername = String(user.username || "").toLowerCase().replace(/[\s@]/g, "");
            const isPrimaryAdmin = cleanRowUsername === "worldofnads" || cleanRowUsername === "tobiawolaju";
            const isSaving = Boolean(savingUsers[user.username]);
            const looksLikeWallet = user.username?.startsWith("0x") || user.username?.includes(":");
            const handle = user.twitterUsername
              ? `@${user.twitterUsername}`
              : looksLikeWallet
                ? "N/A"
                : `@${user.username}`;

            return (
              <div className="admin-users__row" key={user.username}>
                <span className="admin-users__user">
                  {user.profilePictureUrl ? (
                    <img src={user.profilePictureUrl} alt={user.username} />
                  ) : null}
                  <span>{user.username}</span>
                </span>
                <span>{handle}</span>
                <span>
                  <input type="checkbox" checked={isPlayer} disabled />
                </span>
                <span>
                  <input
                    type="checkbox"
                    checked={isAdmin}
                    disabled={isPrimaryAdmin || isSaving}
                    onChange={() => handleToggle(user.username, "admin")}
                  />
                </span>
                <span>
                  <span className="admin-users__cell">
                    <input
                      type="checkbox"
                      checked={isSponsor}
                      disabled={isSaving}
                      onChange={() => handleToggle(user.username, "sponsor")}
                    />
                    {isSaving ? <span className="admin-users__status">Saving...</span> : null}
                  </span>
                </span>
              </div>
            );
          })
        )}
      </div>
    </div>
  );
};

export default AdminUsers;
