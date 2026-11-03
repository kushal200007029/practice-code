import { useState, useEffect } from "react";
import axios from "axios";

const API = "http://localhost:5000/api/todos";

export default function App() {
  const [todos, setTodos] = useState([]);
  const [input, setInput] = useState("");
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState(null);

  useEffect(() => {
    fetchTodos();
  }, []);

  const fetchTodos = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await axios.get(API);
      setTodos(res.data);
    } catch (err) {
      setError("Failed to load todos");
    } finally {
      setLoading(false);
    }
  };

  const addTodo = async (e) => {
    e.preventDefault();
    if (!input.trim()) return;
    setLoading(true);
    setError(null);
    try {
      const res = await axios.post(API, { text: input });
      setTodos([res.data, ...todos]);
      setInput("");
    } catch (err) {
      setError("Failed to add todo");
    } finally {
      setLoading(false);
    }
  };

  const toggleTodo = async (todo) => {
    setLoading(true);
    setError(null);
    try {
      const res = await axios.patch(`${API}/${todo._id}`, {
        completed: !todo.completed,
        text: todo.text,
      });
      setTodos(
        todos.map((t) => (t._id === res.data._id ? res.data : t))
      );
    } catch (err) {
      setError("Failed to update todo");
    } finally {
      setLoading(false);
    }
  };

  const deleteTodo = async (id) => {
    setLoading(true);
    setError(null);
    try {
      await axios.delete(`${API}/${id}`);
      setTodos(todos.filter((t) => t._id !== id));
    } catch (err) {
      setError("Failed to delete todo");
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="todo-app">
      <h1>Todo App</h1>
      {error && (
        <div style={{ color: "#dc2626", marginBottom: 12, textAlign: "center" }}>
          {error}
        </div>
      )}
      {loading && <div style={{ textAlign: "center" }}>Loading...</div>}
      <form onSubmit={addTodo} className="todo-form">
        <input
          type="text"
          className="todo-input"
          placeholder="Add a new todo..."
          value={input}
          onChange={(e) => setInput(e.target.value)}
          disabled={loading}
        />
        <button type="submit" className="add-btn" disabled={loading}>
          Add
        </button>
      </form>
      {todos.length === 0 && !loading && !error ? (
        <div className="empty-state">No todos yet. Add one above!</div>
      ) : (
        <ul className="todo-list">
          {todos.map((todo) => (
            <li key={todo._id} className={`todo-item ${todo.completed ? "completed" : ""}`}>
              <div className="todo-content">
                <input
                  type="checkbox"
                  className="todo-checkbox"
                  checked={todo.completed}
                  onChange={() => toggleTodo(todo)}
                />
                <span className="todo-text">{todo.text}</span>
              </div>
              <div className="todo-actions">
                <button
                  type="button"
                  className="icon-btn edit-btn"
                  onClick={() => {
                    const text = window.prompt("Edit todo", todo.text);
                    if (text !== null && text.trim()) {
                      setLoading(true);
                      axios
                        .patch(`${API}/${todo._id}`, { text: text.trim() })
                        .then((res) =>
                          setTodos(
                            todos.map((t) =>
                              t._id === res.data._id ? res.data : t
                            )
                          )
                        )
                        .catch(() => setError("Failed to update todo"))
                        .finally(() => setLoading(false));
                    }
                  }}
                  title="Edit"
                >
                  ✏️
                </button>
                <button
                  type="button"
                  className="icon-btn delete-btn"
                  onClick={() => deleteTodo(todo._id)}
                  title="Delete"
                >
                  🗑️
                </button>
              </div>
            </li>
          ))}
        </ul>
      )}
    </div>
  );
}
