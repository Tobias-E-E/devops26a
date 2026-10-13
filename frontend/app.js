const itemsList = document.getElementById("items");
const form = document.getElementById("new-item-form");
const textInput = document.getElementById("item-text");

async function loadItems() {
  const response = await fetch("/api/items");
  const items = await response.json();
  renderItems(items);
}

function renderItems(items) {
  itemsList.innerHTML = "";
  for (const item of items) {
    const li = document.createElement("li");

    const span = document.createElement("span");
    span.textContent = item.text;
    li.appendChild(span);

    const deleteButton = document.createElement("button");
    deleteButton.textContent = "Delete";
    deleteButton.addEventListener("click", () => deleteItem(item.id));
    li.appendChild(deleteButton);

    itemsList.appendChild(li);
  }
}

async function deleteItem(id) {
  await fetch(`/api/items/${id}`, { method: "DELETE" });
  await loadItems();
}

form.addEventListener("submit", async (event) => {
  event.preventDefault();
  const text = textInput.value.trim();
  if (!text) return;

  await fetch("/api/items", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ text }),
  });

  textInput.value = "";
  await loadItems();
});

loadItems();
